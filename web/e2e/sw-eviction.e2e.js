// 같은 오리진에 남은 옛 서비스 워커를 로그인 페이지가 밀어내는지 검증하는 E2E 스크립트
//
// 재현하는 사건: 포트 5500(Live Server 기본값)을 쓰던 다른 프로젝트의 "클린 URL" 워커가
// 오리진에 남아 detect.html 내비게이션을 301로 /detect에 보내고, 정적 서버가 404를 낸다.
// 로그인 페이지 방문만으로 우리 sw.js(skipWaiting/claim)가 그 워커를 대체해야 한다.
//
// 백엔드가 필요 없고 서버도 스스로 띄우므로 단독 실행된다. 브라우저는 시스템 Chrome을 쓴다.
// 실행: cd web && npm run test:e2e:sw

import assert from "node:assert/strict";
import http from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const PORT = 5641; // 실제 5500 서버와 충돌하지 않는 전용 포트
const WEB = `http://127.0.0.1:${PORT}`;
const ROOT = fileURLToPath(new URL("..", import.meta.url));

// 실제 사건과 같은 메커니즘의 픽스처 — *.html 내비게이션을 확장자 없는 경로로 301 리다이렉트.
// 이름에 주의: "legacy-sw.js"처럼 sw.js로 끝나면 아래 endsWith("/sw.js") 판정이 헛통과한다.
const OLD_WORKER = `
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.mode === "navigate" && url.pathname.endsWith(".html")) {
    e.respondWith(Response.redirect(url.pathname.slice(0, -".html".length), 301));
  }
});
`;

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json",
};

const server = http.createServer(async (req, res) => {
  const pathname = new URL(req.url, WEB).pathname;
  if (pathname === "/old-worker.js") {
    res.writeHead(200, { "Content-Type": "text/javascript", "Cache-Control": "no-store" });
    return res.end(OLD_WORKER);
  }
  const rel = pathname === "/" ? "index.html" : pathname.slice(1);
  try {
    const file = await readFile(join(ROOT, normalize(rel)));
    res.writeHead(200, {
      "Content-Type": MIME[extname(rel)] ?? "application/octet-stream",
      "Cache-Control": "no-store",
    });
    res.end(file);
  } catch {
    // python http.server처럼 없는 경로는 404 — /detect가 실패하는 조건을 그대로 만든다
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("File not found");
  }
});
await new Promise((resolve) => server.listen(PORT, "127.0.0.1", resolve));

async function step(name, fn) {
  await fn();
  console.log(`  ✅ ${name}`);
}

const browser = await chromium.launch({ channel: "chrome" });
try {
  const page = await browser.newPage();

  await step("옛 워커가 오리진을 잡는다", async () => {
    // signup.html은 워커 등록 코드가 없는 페이지라 심기에 간섭이 없다
    await page.goto(`${WEB}/signup.html`);
    await page.evaluate(async () => {
      await navigator.serviceWorker.register("/old-worker.js");
      await navigator.serviceWorker.ready;
    });
    await page.waitForFunction(() =>
      navigator.serviceWorker.controller?.scriptURL.endsWith("/old-worker.js"),
    );
  });

  await step("옛 워커가 detect.html을 /detect(404)로 보낸다 — 버그 재현", async () => {
    const res = await page.goto(`${WEB}/detect.html`);
    assert.equal(new URL(res.url()).pathname, "/detect");
    assert.equal(res.status(), 404);
  });

  await step("로그인 페이지 방문만으로 우리 워커가 제어권을 되찾는다", async () => {
    await page.goto(`${WEB}/`);
    await page.waitForFunction(
      () => navigator.serviceWorker.controller?.scriptURL.endsWith("/sw.js"),
      undefined,
      { timeout: 8000 },
    );
  });

  await step("이후 detect.html 내비게이션은 리다이렉트 없이 200으로 열린다", async () => {
    const res = await page.goto(`${WEB}/detect.html`);
    assert.equal(new URL(res.url()).pathname, "/detect.html");
    assert.equal(res.status(), 200);
  });

  console.log("\n워커 축출 E2E 통과");
} finally {
  await browser.close();
  server.close();
}
