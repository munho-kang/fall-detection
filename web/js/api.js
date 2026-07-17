// Django API 호출 래퍼와 토큰 보관

// Render에 배포한 백엔드 주소. Render 대시보드에 표시되는 실제 URL로 바꾼다. 끝에 / 없이.
const PROD_API_BASE = "https://fall-backend-XXXX.onrender.com";

// 로컬에서 열면(개발) 로컬 Django를, GitHub Pages에서 열면 Render 백엔드를 쓴다.
const isLocalhost = ["127.0.0.1", "localhost"].includes(location.hostname);
export const API_BASE = isLocalhost ? "http://127.0.0.1:8000" : PROD_API_BASE;

const TOKEN_KEY = "fall_token";

export const getToken = () => localStorage.getItem(TOKEN_KEY);
export const setToken = (t) => localStorage.setItem(TOKEN_KEY, t);
export const clearToken = () => localStorage.removeItem(TOKEN_KEY);

export function logoutAndRedirect() {
  clearToken();
  location.href = "index.html";
}

export function requireToken() {
  const token = getToken();
  if (!token) location.href = "index.html";
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

// 최대 3회 시도, 사이에 지수 백오프(0.5s → 1s)를 둔다. 마지막 시도가 실패하면
// 기다리지 않고 바로 포기하므로 배너까지 약 1.5초다. 3회 실패하면 이 낙상은 유실된다.
// 실제 제품이라면 localStorage 큐가 필요하지만 과제 범위에서는 배너로 알리고 포기한다.
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
