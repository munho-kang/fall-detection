// 데스크톱 브라우저 웹 푸시 E2E — 실제 Chrome에서 구독→발송→서비스 워커 알림 표시까지 검증한다
//
// 시나리오
//  1) 새 계정 가입 (node에서 직접 API 호출)
//  2) index.html?next=guardian.html 에서 UI 로그인 → guardian.html 리다이렉트 확인
//  3) 알림 권한을 미리 부여하고 "알림 켜기" 클릭
//     → VAPID 공개키 수신 → pushManager.subscribe → POST /api/push/devices/ 201
//  4) node에서 새 낙상 POST (fresh occurred_at → 201 → 서버가 pywebpush 발송)
//  5) 페이지에서 서비스 워커 registration.getNotifications() 폴링
//     → "낙상 감지" 알림이 표시됐는지 확인
//
// 사용법: node push-e2e.mjs [--headed]   (헤드리스에서 푸시 수신이 안 되면 --headed로 재시도)

import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { chromium } from "playwright-core";

const WEB = "http://127.0.0.1:5500";
const API = "http://127.0.0.1:8000";
const headless = !process.argv.includes("--headed");

let failed = 0;
const check = (cond, label) => {
  console.log(`${cond ? "통과" : "실패"} — ${label}`);
  if (!cond) failed += 1;
};

// 1) 계정 준비
const username = `e2e_push_${Date.now()}`;
const password = "wenivE2e!2026";
const signupRes = await fetch(`${API}/api/auth/signup/`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ username, password }),
});
if (!signupRes.ok) throw new Error(`가입 실패 ${signupRes.status}`);
const { token } = await signupRes.json();
console.log(`계정 생성: ${username} (headless=${headless})`);

// 시크릿(incognito) 컨텍스트에서는 Chrome이 Push API를 막으므로 일반 프로필로 띄운다.
// Playwright 기본 인자 --disable-background-networking은 푸시 수신용 GCM 소켓을 꺼버리므로 제거한다.
const profileDir = mkdtempSync(join(tmpdir(), "push-e2e-profile-"));
const context = await chromium.launchPersistentContext(profileDir, {
  channel: "chrome",
  headless,
  ignoreDefaultArgs: ["--disable-background-networking"],
});
try {
  await context.grantPermissions(["notifications"], { origin: WEB });
  const page = await context.newPage();
  page.on("console", (m) => {
    if (m.type() === "error") console.log(`  [브라우저 콘솔 오류] ${m.text()}`);
  });

  // 2) UI 로그인 → next 리다이렉트
  await page.goto(`${WEB}/index.html?next=guardian.html`);
  await page.fill("#username", username);
  await page.fill("#password", password);
  await page.click("form button[type=submit]");
  await page.waitForURL("**/guardian.html", { timeout: 10_000 });
  check(true, "로그인 후 guardian.html로 리다이렉트");

  // 3) 알림 켜기 → 구독 + 서버 등록
  const deviceRegistered = page
    .waitForResponse(
      (res) => res.url().endsWith("/api/push/devices/") && res.request().method() === "POST",
      { timeout: 20_000 }
    )
    .catch(() => null); // 구독 실패 시 상태 문구 검사에서 원인이 드러난다
  await page.click("#enablePush");
  const status = page.locator("#pushStatus");
  await status.filter({ hasText: /알림이 켜졌습니다|않습니다|실패|거부/ }).waitFor({ timeout: 20_000 });
  const statusText = (await status.textContent()).trim();
  check(statusText === "알림이 켜졌습니다.", `구독 상태 문구: "${statusText}"`);
  const regRes = await deviceRegistered;
  check(regRes?.status() === 201, `POST /api/push/devices/ → ${regRes?.status() ?? "없음"} (기대 201)`);

  const sub = await page.evaluate(async () => {
    const reg = await navigator.serviceWorker.ready;
    const s = await reg.pushManager.getSubscription();
    return s ? new URL(s.endpoint).host : null;
  });
  check(sub != null, `브라우저 푸시 구독 존재 (엔드포인트 호스트: ${sub})`);

  // 4) 새 낙상 POST → 서버가 웹 푸시 발송.
  // 발송 TTL이 0이라(즉시 전달 아니면 폐기) 새 프로필의 GCM 소켓이 붙을 시간을 먼저 준다.
  await page.waitForTimeout(8_000);

  const postFall = async (label) => {
    const payload = {
      room_name: "부엌",
      room_number: 3,
      occurred_at: new Date().toISOString(), // 멱등 흡수를 피하려고 매번 새 시각
      confidence: 0.93,
    };
    const res = await fetch(`${API}/api/falls/`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Token ${token}` },
      body: JSON.stringify(payload),
    });
    check(res.status === 201, `낙상 POST(${label}) → ${res.status} (기대 201 — 201일 때만 푸시 발송)`);
  };
  // 알림이 짧게 떴다 닫혀도 잡히도록, 감지와 스냅숏을 한 evaluate 안에서 100ms 간격으로 샘플링한다
  const sampleNotifications = (ms) =>
    page.evaluate(async (timeout) => {
      const reg = await navigator.serviceWorker.ready;
      const t0 = Date.now();
      while (Date.now() - t0 < timeout) {
        const list = await reg.getNotifications();
        if (list.length) return list.map((n) => ({ title: n.title, body: n.body, tag: n.tag }));
        await new Promise((r) => setTimeout(r, 100));
      }
      return [];
    }, ms);

  await postFall("1차");
  let notis = await sampleNotifications(30_000);
  if (notis.length === 0) {
    // 소켓 지연 진단용 — 2차가 도착하면 연결 타이밍 문제, 2차도 안 오면 구조적 문제다
    console.log("  1차 미수신 — 15초 뒤 2차 발송으로 타이밍/구조 문제를 가른다");
    await page.waitForTimeout(15_000);
    await postFall("2차");
    notis = await sampleNotifications(30_000);
  }

  // 5) 서비스 워커가 표시한 알림 확인
  check(notis.length > 0, `푸시 수신 후 알림 표시 (${notis.length}건)`);
  if (notis.length > 0) {
    const n = notis[0];
    check(n.title === "낙상 감지", `알림 제목: "${n.title}"`);
    check(n.body === "부엌 3에서 낙상 감지", `알림 본문: "${n.body}"`);
    check(n.tag?.startsWith("fall-"), `알림 태그(중복 병합용): "${n.tag}"`);
  }
} finally {
  await context.close();
}

console.log(failed === 0 ? "\n웹 푸시 E2E 전부 통과" : `\n실패 ${failed}건`);
process.exit(failed === 0 ? 0 : 1);
