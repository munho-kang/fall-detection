// Django API 호출 래퍼와 토큰 보관

// 정적 서버(:5500)와 Django(:8000)는 같은 Mac에서 뜬다. 같은 와이파이의 다른 기기가
// http://<Mac IP>:5500으로 열어도, 접속한 호스트가 곧 Django 호스트다.
export const API_BASE = `http://${location.hostname}:8000`;

const TOKEN_KEY = "fall_token";

export const getToken = () => localStorage.getItem(TOKEN_KEY);
export const setToken = (t) => localStorage.setItem(TOKEN_KEY, t);
export const clearToken = () => localStorage.removeItem(TOKEN_KEY);

export function logoutAndRedirect() {
  clearToken();
  location.href = "index.html";
}

export function requireToken(next) {
  const token = getToken();
  // 로그인 후 원래 가려던 페이지로 돌아올 수 있게 next를 남긴다 (index.html이 화이트리스트 검사)
  if (!token) location.href = next ? `index.html?next=${encodeURIComponent(next)}` : "index.html";
  return token;
}

export async function login(username, password) {
  const res = await fetch(`${API_BASE}/api/auth/login/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error("아이디 또는 비밀번호가 올바르지 않습니다.");
  const { token } = await res.json();
  return token;
}

export async function signup(username, password) {
  const res = await fetch(`${API_BASE}/api/auth/signup/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error(await firstErrorMessage(res, "회원가입에 실패했습니다."));
  const { token } = await res.json();
  return token; // 가입 즉시 발급된 토큰 — 별도 로그인이 필요 없다
}

class UnauthorizedError extends Error {}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function postFallOnce(payload) {
  const res = await fetch(`${API_BASE}/api/falls/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Token ${getToken()}`,
    },
    body: JSON.stringify(payload),
  });
  if (res.status === 401) throw new UnauthorizedError();
  if (!res.ok) throw new Error(`서버가 ${res.status}를 반환했습니다.`);
  return res.json();
}

// 최대 3회 시도, 사이에 지수 백오프(0.5s → 1s)를 둔다. 3회 실패하면 호출자(main.js)가
// localStorage 큐에 적재해 두었다가 연결이 돌아오면 재전송한다. 서버의 unique 제약이
// 재전송 중복을 200으로 흡수하므로 여러 번 보내져도 행이 늘지 않는다.
export async function postFall(payload, attempts = 3) {
  for (let i = 0; i < attempts; i += 1) {
    try {
      return await postFallOnce(payload);
    } catch (err) {
      if (err instanceof UnauthorizedError) {
        logoutAndRedirect(); // 토큰이 죽었으면 재시도는 무의미하다
        throw err;
      }
      if (i === attempts - 1) throw err;
      await sleep(500 * 2 ** i);
    }
  }
}

// DRF 검증 에러({필드: [메시지, ...]})의 첫 메시지를 꺼낸다. 한국어로 내려온다.
async function firstErrorMessage(res, fallback) {
  try {
    const first = Object.values(await res.json()).flat()[0];
    if (typeof first === "string") return first;
  } catch {
    // 본문이 JSON이 아니면 기본 문구를 쓴다
  }
  return fallback;
}

// 토큰을 붙여 호출하고 401이면 로그아웃까지 처리하는 공통 래퍼
async function authFetch(path, options = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Token ${getToken()}`,
      ...(options.headers ?? {}),
    },
  });
  if (res.status === 401) {
    logoutAndRedirect();
    throw new UnauthorizedError();
  }
  return res;
}

export async function listRooms() {
  const res = await authFetch("/api/rooms/");
  if (!res.ok) throw new Error(`방 목록을 불러오지 못했습니다 (${res.status}).`);
  return res.json();
}

export async function createRoom(name, number) {
  const res = await authFetch("/api/rooms/", {
    method: "POST",
    body: JSON.stringify({ name, number }),
  });
  if (!res.ok) throw new Error(await firstErrorMessage(res, "방을 추가하지 못했습니다."));
  return res.json();
}

export async function listFalls() {
  const res = await authFetch("/api/falls/");
  if (!res.ok) throw new Error(`목록을 불러오지 못했습니다 (${res.status}).`);
  return res.json();
}

export async function acknowledgeFall(id) {
  const res = await authFetch(`/api/falls/${id}/acknowledge/`, { method: "POST" });
  if (!res.ok) throw new Error(`확인 처리에 실패했습니다 (${res.status}).`);
  return res.json();
}

export async function deleteFall(id) {
  const res = await authFetch(`/api/falls/${id}/`, { method: "DELETE" });
  // 미확인 기록 삭제는 서버가 400 + 한국어 문구로 거절한다. 문구를 새로 짓지 말고 그대로 올린다.
  if (!res.ok) {
    throw new Error(await firstErrorMessage(res, `기록을 삭제하지 못했습니다 (${res.status}).`));
  }
}

export async function renameRoom(id, name) {
  const res = await authFetch(`/api/rooms/${id}/`, {
    method: "PATCH",
    body: JSON.stringify({ name }),
  });
  if (!res.ok) throw new Error(await firstErrorMessage(res, "이름을 바꾸지 못했습니다."));
  return res.json();
}

export async function deleteRoomById(id) {
  const res = await authFetch(`/api/rooms/${id}/`, { method: "DELETE" });
  if (!res.ok) throw new Error(`방을 삭제하지 못했습니다 (${res.status}).`);
}

export async function getProfile() {
  const res = await authFetch("/api/profile/");
  if (!res.ok) throw new Error(`연락처를 불러오지 못했습니다 (${res.status}).`);
  return res.json();
}

export async function updateProfile(elderPhone) {
  const res = await authFetch("/api/profile/", {
    method: "PUT",
    body: JSON.stringify({ elder_phone: elderPhone }),
  });
  if (!res.ok) throw new Error(await firstErrorMessage(res, "연락처를 저장하지 못했습니다."));
  return res.json();
}

export async function getVapidKey() {
  const res = await authFetch("/api/push/vapid-key/");
  if (res.status === 503) throw new Error("서버에 웹 푸시 키가 설정되지 않았습니다.");
  if (!res.ok) throw new Error(`푸시 키를 가져오지 못했습니다 (${res.status}).`);
  return res.json(); // { key }
}

export async function registerPushDevice(kind, token) {
  const res = await authFetch("/api/push/devices/", {
    method: "POST",
    body: JSON.stringify({ kind, token }),
  });
  if (!res.ok) throw new Error(`알림 등록에 실패했습니다 (${res.status}).`);
}

export async function deletePushDevice(token) {
  const res = await authFetch("/api/push/devices/", {
    method: "DELETE",
    body: JSON.stringify({ token }),
  });
  if (!res.ok) throw new Error(`알림 해제에 실패했습니다 (${res.status}).`);
}
