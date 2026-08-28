// 옛 서비스 워커 축출 전용 — 등록 즉시 제어권을 가져오는 것 외에는 아무것도 하지 않는다
//
// 같은 오리진(포트 5500은 Live Server 기본값)에 남은 옛 워커가 제어권을 계속 쥐면
// 페이지 이동을 가로챈다. 이 워커가 즉시 인계받아 그 상태를 만들지 않는다.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
