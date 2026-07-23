// 웹 푸시 수신 서비스 워커 — 알림 표시와 클릭 시 보호자 페이지 열기만 한다

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    // JSON이 아니면 기본 문구로 표시한다
  }
  const body =
    data.room_name != null
      ? `${data.room_name} ${data.room_number}에서 낙상 감지`
      : "낙상이 감지되었습니다";
  event.waitUntil(
    self.registration.showNotification("낙상 감지", {
      body,
      tag: data.id != null ? `fall-${data.id}` : undefined, // 같은 낙상 재수신은 하나로 합친다
      icon: "icons/icon-192.png",
      data,
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((wins) => {
      const existing = wins.find((w) => w.url.includes("guardian.html"));
      return existing ? existing.focus() : self.clients.openWindow("./guardian.html");
    })
  );
});
