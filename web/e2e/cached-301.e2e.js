// 캐시에 박힌 301(detect.html → /detect)을 로그인 흐름이 무력화하는지 검증하는 E2E 스크립트
//
// 재현하는 사건: 7/17에 clean-URL 서버(npx serve류)가 GET /detect.html에 301 → /detect를 냈고
// Chrome이 이를 디스크 캐시에 저장해, python http.server로 바뀐 뒤에도 네트워크에 묻지 않고
// 열흘간 재생했다. DevTools의 Clear site data로도 HTTP 캐시는 지워지지 않아 증상이 유지됐다.
// 로그인 페이지는 (1) 이동 URL에 캐시 버스터를 붙여 오염된 키를 우회하고
// (2) fetch(cache:"reload")로 오염 항목 자체를 정상 200으로 덮어써야 한다.
//
// 301 재생은 디스크 캐시에서 일어나므로 임시 프로필로 launchPersistentContext를 쓴다.
// 로그인은 실제 백엔드로 한다 — cd backend && ./gradlew bootRun (127.0.0.1:8000)
// 실행: cd web && npm run test:e2e:301

import assert from "node:assert/strict";
import http from "node:http";
import { readFile, stat, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const PORT = 5642; // 실제 5500 서버·다른 e2e(5641)와 충돌하지 않는 전용 포트
const WEB = `http://127.0.0.1:${PORT}`;
const API = "http://127.0.0.1:8000";
const PASSWORD = "Sim!Verify2026";
const ROOT = fileURLToPath(new URL("..", import.meta.url));

// 검증마다 새 계정을 쓴다. 로그인 폼을 실제로 통과해야 실제 이동 코드가 실행된다.
async function signup() {
  const username = `cache301_${Date.now()}`;
  const res = await fetch(`${API}/api/auth/signup/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password: PASSWORD }),
  });
  assert.equal(res.status, 201, `가입 실패: ${await res.text()}`);
  return username;
}

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json",
};

// python http.server처럼 Cache-Control 없이 Last-Modified만 준다.
// no-store를 붙이면 검증 대상인 "캐시가 응답을 저장하는 조건" 자체가 사라진다.
async function sendFile(res, rel, extra = {}) {
  const path = join(ROOT, normalize(rel));
  const [file, info] = await Promise.all([readFile(path), stat(path)]);
  res.writeHead(200, {
    "Content-Type": MIME[extname(rel)] ?? "application/octet-stream",
    "Last-Modified": info.mtime.toUTCString(),
    ...extra,
  });
  res.end(file);
}

function send404(res) {
  res.writeHead(404, { "Content-Type": "text/html" });
  res.end("<h1>Error response</h1><p>Error code: 404</p><p>Message: File not found.</p>");
}

// serve 모드는 7/17의 clean-URL 서버, python 모드는 지금의 python http.server를 흉내 낸다.
let mode = "serve";
const server = http.createServer(async (req, res) => {
  const pathname = new URL(req.url, WEB).pathname;
  if (mode === "serve" && pathname === "/detect.html") {
    // 실측 유물(572211ccd14c541d_0)과 같은 형태 — Cache-Control 없는 맨 301
    res.writeHead(301, { Location: "/detect" });
    return res.end();
  }
  if (pathname === "/detect") {
    // 실제 사건에서는 열흘 사이 /detect의 200 캐시만 신선도가 만료되고 301은 남았다.
    // 테스트는 시간이 흐르지 않으므로 그 만료를 no-store로 압축한다.
    if (mode === "serve")
      return sendFile(res, "detect.html", { "Cache-Control": "no-store" }).catch(() => send404(res));
    return send404(res);
  }
  const rel = pathname === "/" ? "index.html" : pathname.slice(1);
  await sendFile(res, rel).catch(() => send404(res));
});
await new Promise((resolve) => server.listen(PORT, "127.0.0.1", resolve));

async function step(name, fn) {
  await fn();
  console.log(`  ✅ ${name}`);
}

const profileDir = await mkdtemp(join(tmpdir(), "fall-cached-301-"));
const context = await chromium.launchPersistentContext(profileDir, { channel: "chrome" });
try {
  const page = await context.newPage();

  await step("clean-URL 서버 시절 방문이 301을 디스크 캐시에 남긴다", async () => {
    const res = await page.goto(`${WEB}/detect.html`);
    assert.equal(new URL(res.url()).pathname, "/detect");
    assert.equal(res.status(), 200);
  });

  mode = "python";

  await step("python 서버로 바뀐 뒤에도 캐시된 301이 재생돼 404가 난다 — 버그 재현", async () => {
    const res = await page.goto(`${WEB}/detect.html`);
    assert.equal(new URL(res.url()).pathname, "/detect");
    assert.equal(res.status(), 404);
  });

  await step("그래도 로그인하면 detect.html에 200으로 도착한다", async () => {
    const username = await signup();
    await page.goto(`${WEB}/`);
    await page.fill("#username", username);
    await page.fill("#password", PASSWORD);
    // waitForNavigation은 리다이렉트 체인의 최종 응답을 준다 — 첫 301이 아니라 착지를 판정한다
    const [res] = await Promise.all([
      page.waitForNavigation({ timeout: 8000 }),
      page.click("button[type=submit]"),
    ]);
    const landed = new URL(res.url());
    assert.equal(landed.pathname, "/detect.html", `실제 도착: ${landed.pathname} (${res.status()})`);
    assert.equal(res.status(), 200);
  });

  await step("로그인 페이지 방문이 오염 항목을 덮어써, 쿼리 없는 detect.html도 200이 된다", async () => {
    const res = await page.goto(`${WEB}/detect.html`);
    assert.equal(new URL(res.url()).pathname, "/detect.html");
    assert.equal(res.status(), 200);
  });

  console.log("\n캐시된 301 무력화 E2E 통과");
} finally {
  await context.close();
  server.close();
  await rm(profileDir, { recursive: true, force: true });
}
