// 보호자 페이지 조립 — 낙상 목록 폴링·확인, 방/연락처 관리, 로그아웃

import {
  acknowledgeFall,
  createRoom,
  deletePushDevice,
  deleteRoomById,
  getProfile,
  getVapidKey,
  listFalls,
  listRooms,
  logoutAndRedirect,
  registerPushDevice,
  renameRoom,
  requireToken,
  updateProfile,
} from "./api.js";
import { pollFailureBanner } from "./pollBanner.js";

requireToken("guardian.html");

const el = {};
for (const id of [
  "banner", "pollBanner", "enablePush", "pushStatus", "fallEmpty", "fallList",
  "roomList", "newRoomName", "newRoomNumber", "addRoomBtn",
  "elderPhone", "savePhone", "error", "logout",
]) {
  el[id] = document.getElementById(id);
}

function showError(err) {
  el.error.textContent = err.message ?? String(err);
}

const two = (n) => String(n).padStart(2, "0");
const fmt = (iso) => {
  const t = new Date(iso);
  return `${t.getMonth() + 1}월 ${t.getDate()}일 ${two(t.getHours())}:${two(t.getMinutes())}`;
};

// --- 낙상 목록 (5초 폴링, 앱 fall_list와 동등) ---

async function refreshFalls() {
  const falls = await listFalls();
  el.fallEmpty.classList.toggle("hidden", falls.length > 0);
  el.fallList.innerHTML = "";
  for (const f of falls) {
    const li = document.createElement("li");
    const label = document.createElement("span");
    label.textContent =
      `${f.room_name} ${f.room_number} · ${fmt(f.occurred_at)} · ` +
      (f.acknowledged_at ? "확인함" : "미확인");
    li.append(label);
    if (!f.acknowledged_at) {
      const btn = document.createElement("button");
      btn.textContent = "확인";
      btn.addEventListener("click", () =>
        acknowledgeFall(f.id).then(refreshFalls).catch(showError)
      );
      li.append(btn);
    }
    el.fallList.append(li);
  }
}

// --- 방 관리 ---

async function refreshRooms() {
  const rooms = await listRooms();
  el.roomList.innerHTML = "";
  for (const room of rooms) {
    const li = document.createElement("li");
    const label = document.createElement("span");
    label.textContent = `${room.name} ${room.number}`;

    const rename = document.createElement("button");
    rename.textContent = "이름 변경";
    rename.addEventListener("click", () => {
      const name = prompt("새 이름", room.name);
      if (name) renameRoom(room.id, name.trim()).then(refreshRooms).catch(showError);
    });

    const del = document.createElement("button");
    del.textContent = "삭제";
    del.addEventListener("click", () => {
      // 과거 낙상 기록은 문자열 스냅샷이라 방을 지워도 깨지지 않는다
      if (confirm(`${room.name} ${room.number} 방을 삭제할까요?`)) {
        deleteRoomById(room.id).then(refreshRooms).catch(showError);
      }
    });

    li.append(label, rename, del);
    el.roomList.append(li);
  }
}

el.addRoomBtn.addEventListener("click", () => {
  el.error.textContent = "";
  createRoom(el.newRoomName.value.trim(), Number(el.newRoomNumber.value))
    .then(() => {
      el.newRoomName.value = "";
      refreshRooms();
    })
    .catch(showError);
});

// --- 어르신 연락처 ---

el.savePhone.addEventListener("click", () => {
  el.error.textContent = "";
  updateProfile(el.elderPhone.value.trim())
    .then(() => {
      el.banner.textContent = "저장했습니다.";
      el.banner.classList.remove("hidden");
      setTimeout(() => el.banner.classList.add("hidden"), 2000);
    })
    .catch(showError);
});

// --- 웹 푸시 ---

function urlBase64ToUint8Array(base64) {
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const raw = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (ch) => ch.charCodeAt(0));
}

const pushSupported = () => "serviceWorker" in navigator && "PushManager" in window;

async function initPushUi() {
  if (!pushSupported()) {
    el.enablePush.disabled = true;
    el.pushStatus.textContent =
      "이 브라우저는 웹 푸시를 지원하지 않습니다. iPhone은 홈 화면에 추가한 뒤 열면 켤 수 있습니다 (iOS 16.4+).";
    return;
  }
  // 어떤 경로에서 서빙되든 동작하도록 상대 경로로 등록한다 (스코프 = 현재 디렉터리)
  const reg = await navigator.serviceWorker.register("./sw.js");
  const sub = await reg.pushManager.getSubscription();
  if (sub) {
    el.enablePush.disabled = true;
    el.pushStatus.textContent = "알림이 켜져 있습니다.";
  }
}

el.enablePush.addEventListener("click", async () => {
  el.pushStatus.textContent = "";
  try {
    const reg = await navigator.serviceWorker.register("./sw.js");
    if ((await Notification.requestPermission()) !== "granted") {
      throw new Error("알림 권한이 거부되었습니다. 브라우저 설정에서 허용해 주세요.");
    }
    const { key } = await getVapidKey();
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key),
    });
    await registerPushDevice("webpush", JSON.stringify(sub));
    el.enablePush.disabled = true;
    el.pushStatus.textContent = "알림이 켜졌습니다.";
  } catch (err) {
    el.pushStatus.textContent = err.message;
  }
});

initPushUi().catch(() => {});

// --- 로그아웃 ---

el.logout.addEventListener("click", async () => {
  try {
    // 이 브라우저 구독을 서버에서 지운다. 실패해도 로그아웃은 진행한다 —
    // 남은 구독은 다음 발송 때 404/410으로 서버가 정리한다.
    const reg = await navigator.serviceWorker.getRegistration();
    const sub = await reg?.pushManager.getSubscription();
    if (sub) {
      await deletePushDevice(JSON.stringify(sub));
      await sub.unsubscribe();
    }
  } catch {
    // 무시
  }
  logoutAndRedirect();
});

// --- 초기화 ---

let pollFailures = 0;
let lastPollSuccessAt = null;

function updatePollBanner() {
  const text = pollFailureBanner(pollFailures, lastPollSuccessAt);
  el.pollBanner.classList.toggle("hidden", !text);
  if (text) el.pollBanner.textContent = text;
}

refreshFalls().catch(showError);
setInterval(() => {
  refreshFalls()
    .then(() => {
      pollFailures = 0;
      lastPollSuccessAt = new Date();
    })
    .catch(() => (pollFailures += 1))
    .finally(updatePollBanner);
}, 5000);
refreshRooms().catch(showError);
getProfile()
  .then((p) => {
    el.elderPhone.value = p.elder_phone;
  })
  .catch(showError);
