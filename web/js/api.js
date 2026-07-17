// Django API 호출 래퍼와 토큰 보관

export const API_BASE = "http://127.0.0.1:8000";

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
