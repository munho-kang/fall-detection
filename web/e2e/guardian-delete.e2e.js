// 보호자 페이지 낙상 기록 삭제를 실제 Chrome에서 검증하는 E2E 스크립트
//
// docs/manual-verification.md 7절의 "보호자 페이지 (웹)"와 웹 쪽 동기화 항목을 자동으로 밟는다.
// 브라우저는 내려받지 않고 시스템에 깔린 Chrome을 그대로 쓴다(channel: "chrome").
//
// 실행 전 둘 다 떠 있어야 한다.
//   cd backend && ./gradlew bootRun        # 127.0.0.1:8000
//   cd web && npx --yes serve -l 5500 .    # 127.0.0.1:5500
// 실행: cd web && npm run test:e2e

import assert from "node:assert/strict";
import { chromium } from "playwright";

const API = "http://127.0.0.1:8000";
const WEB = "http://127.0.0.1:5500";
const PASSWORD = "Sim!Verify2026";

// 검증마다 새 계정을 쓴다. 앞선 실행이 남긴 기록이 목록에 섞이면 판정이 흔들린다.
async function signup() {
  const user = `webe2e_${Date.now()}`;
  const res = await fetch(`${API}/api/auth/signup/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username: user, password: PASSWORD }),
  });
  const body = await res.text();
  assert.equal(res.status, 201, `가입 실패: ${body}`);
  return JSON.parse(body).token;
}

async function seedFall(token, roomName, roomNumber) {
  const res = await fetch(`${API}/api/falls/`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Token ${token}` },
    body: JSON.stringify({
      room_name: roomName,
      room_number: roomNumber,
      occurred_at: new Date().toISOString(),
      confidence: 0.9,
    }),
  });
  const body = await res.text();
  assert.equal(res.status, 201, `낙상 생성 실패: ${body}`);
  return JSON.parse(body).id;
}

async function countFallsOnServer(token) {
  const res = await fetch(`${API}/api/falls/`, { headers: { Authorization: `Token ${token}` } });
  return (await res.json()).length;
}

async function step(name, fn) {
  await fn();
  console.log(`  ✅ ${name}`);
}

/// 낙상 목록 첫 행의 라벨과 버튼 텍스트를 읽는다. 버튼 개수도 함께 준다.
function readFirstRow(page) {
  return page.evaluate(() => {
    const li = document.querySelector("#fallList li");
    if (!li) return null;
    return {
      label: li.querySelector("span").textContent,
      buttons: [...li.querySelectorAll("button")].map((b) => b.textContent),
    };
  });
}

const rowCount = (page) => page.evaluate(() => document.querySelectorAll("#fallList li").length);

const browser = await chromium.launch({ channel: "chrome" });
try {
  // ---- 보호자 페이지 (웹) 4개 항목 ----
  console.log("보호자 페이지 (웹)");
  {
    const token = await signup();
    await seedFall(token, "안방", 1);

    const page = await browser.newPage();
    await page.addInitScript((t) => localStorage.setItem("fall_token", t), token);
    await page.goto(`${WEB}/guardian.html`);
    await page.waitForSelector("#fallList li");

    await step('미확인 기록에 "확인" 버튼만 있고 삭제 버튼이 없다', async () => {
      const row = await readFirstRow(page);
      assert.match(row.label, /미확인$/);
      assert.deepEqual(row.buttons, ["확인"]);
    });

    await step('"확인"을 누르면 상태가 확인함이 되고 버튼이 "삭제"로 바뀐다 (버튼은 항상 하나다)', async () => {
      await page.click("#fallList li button");
      await page.waitForFunction(
        () => document.querySelector("#fallList li span").textContent.endsWith("확인함"),
      );
      const row = await readFirstRow(page);
      assert.deepEqual(row.buttons, ["삭제"]);
    });

    await step('"삭제"를 누르면 확인창이 뜨고, 취소하면 기록이 그대로다', async () => {
      const dismissed = new Promise((resolve) => {
        page.once("dialog", async (d) => {
          const message = d.message();
          await d.dismiss();
          resolve(message);
        });
      });
      await page.click("#fallList li button");
      assert.match(await dismissed, /낙상 기록을 삭제할까요\?$/);
      assert.equal(await rowCount(page), 1);
      assert.equal(await countFallsOnServer(token), 1);
    });

    await step("확인창에서 확인하면 목록에서 사라지고, 새로고침해도 돌아오지 않는다", async () => {
      const accepted = new Promise((resolve) => {
        page.once("dialog", async (d) => {
          await d.accept();
          resolve();
        });
      });
      await page.click("#fallList li button");
      await accepted;
      await page.waitForFunction(() => document.querySelectorAll("#fallList li").length === 0);
      assert.equal(await countFallsOnServer(token), 0);

      await page.reload();
      await page.waitForFunction(
        () => !document.getElementById("fallEmpty").classList.contains("hidden"),
      );
      assert.equal(await rowCount(page), 0);
    });

    await page.close();
  }

  // ---- 양쪽 동기화 (웹이 받는 쪽) ----
  console.log("양쪽 동기화");
  {
    const token = await signup();
    const id = await seedFall(token, "안방", 2);
    await seedFall(token, "거실", 3);

    const page = await browser.newPage();
    await page.addInitScript((t) => localStorage.setItem("fall_token", t), token);
    await page.goto(`${WEB}/guardian.html`);
    await page.waitForFunction(() => document.querySelectorAll("#fallList li").length === 2);

    await step("앱에서 삭제한 기록이 웹 목록에서도 5초 안에 사라진다", async () => {
      // 앱이 보내는 것과 같은 요청이다 — 확인한 뒤 DELETE.
      await fetch(`${API}/api/falls/${id}/acknowledge/`, {
        method: "POST",
        headers: { Authorization: `Token ${token}` },
      });
      const res = await fetch(`${API}/api/falls/${id}/`, {
        method: "DELETE",
        headers: { Authorization: `Token ${token}` },
      });
      assert.equal(res.status, 204);

      // 웹은 아무 조작도 하지 않는다. 폴링 한 주기만 기다린다.
      await page.waitForFunction(
        () => document.querySelectorAll("#fallList li").length === 1,
        undefined,
        { timeout: 6000 },
      );
      const row = await readFirstRow(page);
      assert.match(row.label, /^거실 3 /);
    });

    await step("삭제 후 새 낙상이 오면 목록에 정상으로 뜬다", async () => {
      await seedFall(token, "주방", 4);
      await page.waitForFunction(
        () => document.querySelectorAll("#fallList li").length === 2,
        undefined,
        { timeout: 6000 },
      );
      const labels = await page.evaluate(() =>
        [...document.querySelectorAll("#fallList li span")].map((s) => s.textContent),
      );
      assert.match(labels[0], /^주방 4 /);
    });

    await page.close();
  }

  console.log("\n웹 E2E 6건 전부 통과");
} finally {
  await browser.close();
}
