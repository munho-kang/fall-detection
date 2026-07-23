// 낙상 목록 폴링의 연속 실패 횟수·마지막 성공 시각으로 갱신 실패 배너 문구를 정하는 순수 함수

export function pollFailureBanner(consecutiveFailures, lastSuccessAt) {
  if (consecutiveFailures < 3) return null; // 배너 숨김
  if (!lastSuccessAt) return "목록 갱신 실패";
  const two = (n) => String(n).padStart(2, "0");
  return `목록 갱신 실패 — 마지막 갱신 ${two(lastSuccessAt.getHours())}:${two(lastSuccessAt.getMinutes())}`;
}
