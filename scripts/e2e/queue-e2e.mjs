// 감지 페이지 오프라인→온라인 큐 재전송 E2E — 실제 Chrome에서 detect.html의 flush 배선을 검증한다
//
// 시나리오
//  1) 새 계정 가입 → 토큰 확보 (node에서 직접 API 호출)
//  2) localStorage에 토큰 + 낙상 2건이 든 fall_queue를 심고, API 오리진을 차단한 채 detect.html 로드
//     → 페이지 로드 flush가 실패해도 큐가 그대로 남아야 한다
//  3) 차단 해제 후 offline→online 전환으로 window 'online' 이벤트 발화
//     → main.js의 flushQueue가 두 건을 순서대로 POST, 큐가 비어야 한다
//  4) 서버 DB(GET /api/falls/)에 두 건이 정확히 도달했는지 확인
//  5) 이미 보낸 건을 다시 큐에 넣고 재발화 → 서버가 200으로 흡수, 행 수 불변(멱등성)

import { chromium } from "playwright-core";

const WEB = "http://127.0.0.1:5500";
const API = "http://127.0.0.1:8000";

let failed = 0;
const check = (cond, label) => {
  console.log(`${cond ? "통과" : "실패"} — ${label}`);
  if (!cond) failed += 1;
};

// 1) 계정 준비
const username = `e2e_queue_${Date.now()}`;
const signupRes = await fetch(`${API}/api/auth/signup/`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ username, password: "wenivE2e!2026" }),
});
if (!signupRes.ok) throw new Error(`가입 실패 ${signupRes.status}`);
const { token } = await signupRes.json();
console.log(`계정 생성: ${username}`);

const base = Date.now() - 60_000;
const p1 = { room_name: "안방", room_number: 1, occurred_at: new Date(base).toISOString(), confidence: 0.91 };
const p2 = { room_name: "거실", room_number: 2, occurred_at: new Date(base + 5000).toISOString(), confidence: 0.87 };

const browser = await chromium.launch({ channel: "chrome", headless: true });
try {
  const context = await browser.newContext();
  await context.addInitScript(([t, queue]) => {
    localStorage.setItem("fall_token", t);
    localStorage.setItem("fall_queue", JSON.stringify(queue));
  }, [token, [p1, p2]]);

  // 2) API만 차단(서버 다운 시뮬레이션) — 정적 파일·CDN은 그대로 로드된다
  await context.route(`${API}/**`, (r) => r.abort());

  const page = await context.newPage();
  const posts = [];
  page.on("request", (req) => {
    if (req.url().startsWith(API) && req.method() === "POST") posts.push(new URL(req.url()).pathname);
  });

  await page.goto(`${WEB}/detect.html`);
  await page.waitForTimeout(2500); // 로드 시 flush 시도가 실패하고 지나가도록

  const blockedLen = await page.evaluate(() => JSON.parse(localStorage.getItem("fall_queue")).length);
  check(blockedLen === 2, `API 차단 중 큐 유지 (${blockedLen}건 남음, 기대 2건)`);
  check(page.url().endsWith("detect.html"), "차단 실패가 로그아웃으로 오인되지 않음 (detect.html 유지)");
  // flush는 head 실패 시 그 자리에서 중단해야 한다 — 차단 중 시도는 정확히 1건
  const blockedPosts = posts.filter((p) => p === "/api/falls/").length;
  check(blockedPosts === 1, `차단 중 POST 시도 = ${blockedPosts} (기대 1 — head 실패 시 중단)`);
  posts.length = 0; // 이후는 재전송 단계만 센다

  // 3) 차단 해제 + 실제 offline→online 전환
  await context.unroute(`${API}/**`);
  await context.setOffline(true);
  await page.waitForTimeout(300);
  await context.setOffline(false);

  await page.waitForFunction(
    () => JSON.parse(localStorage.getItem("fall_queue") ?? "[]").length === 0,
    null,
    { timeout: 10_000 }
  );
  check(true, "online 이벤트 후 10초 안에 큐가 비었음");
  const fallPosts = posts.filter((p) => p === "/api/falls/").length;
  check(fallPosts === 2, `재전송 POST 횟수 = ${fallPosts} (기대 2)`);

  // 4) 서버 DB 확인
  const listRes = await fetch(`${API}/api/falls/`, { headers: { Authorization: `Token ${token}` } });
  const falls = await listRes.json();
  const got = falls.map((f) => [f.room_name, new Date(f.occurred_at).getTime()].join("|")).sort();
  const want = [p1, p2].map((p) => [p.room_name, new Date(p.occurred_at).getTime()].join("|")).sort();
  check(falls.length === 2, `서버에 낙상 ${falls.length}건 (기대 2)`);
  check(JSON.stringify(got) === JSON.stringify(want), "방·발생시각이 큐에 실은 값과 일치");

  // 5) 멱등성 — 같은 건 재전송은 200으로 흡수되고 행이 늘지 않는다
  await page.evaluate((p) => localStorage.setItem("fall_queue", JSON.stringify([p])), p1);
  await context.setOffline(true);
  await page.waitForTimeout(300);
  await context.setOffline(false);
  await page.waitForFunction(
    () => JSON.parse(localStorage.getItem("fall_queue") ?? "[]").length === 0,
    null,
    { timeout: 10_000 }
  );
  const again = await (await fetch(`${API}/api/falls/`, { headers: { Authorization: `Token ${token}` } })).json();
  check(again.length === 2, `중복 재전송 후에도 서버는 ${again.length}건 (기대 2, 200 흡수)`);
} finally {
  await browser.close();
}

console.log(failed === 0 ? "\n큐 재전송 E2E 전부 통과" : `\n실패 ${failed}건`);
process.exit(failed === 0 ? 0 : 1);
