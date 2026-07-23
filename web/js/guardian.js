// 보호자 페이지 조립 — 낙상 목록 폴링·확인, 방/연락처 관리, 로그아웃

import {
  acknowledgeFall,
  createRoom,
  deleteRoomById,
  getProfile,
  listFalls,
  listRooms,
  logoutAndRedirect,
  renameRoom,
  requireToken,
  updateProfile,
} from "./api.js";

requireToken("guardian.html");

const el = {};
for (const id of [
  "banner", "enablePush", "pushStatus", "fallEmpty", "fallList",
  "roomList", "newRoomName", "newRoomNumber", "addRoomBtn",
  "elderPhone", "savePhone", "error", "logout",
]) {
  el[id] = document.getElementById(id);
}

el.enablePush.disabled = true; // Task 11에서 켠다

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

// --- 로그아웃 ---

el.logout.addEventListener("click", () => logoutAndRedirect());

// --- 초기화 ---

refreshFalls().catch(showError);
setInterval(() => refreshFalls().catch(() => {}), 5000); // 폴링 실패는 다음 주기가 흡수한다
refreshRooms().catch(showError);
getProfile()
  .then((p) => {
    el.elderPhone.value = p.elder_phone;
  })
  .catch(showError);
