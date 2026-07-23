// pollBanner.js의 연속 실패 → 갱신 실패 배너 문구 판별 로직 검증
import { describe, expect, it } from "vitest";

import { pollFailureBanner } from "../js/pollBanner.js";

describe("poll failure banner", () => {
  it("연속 실패가 3회 미만이면 배너를 표시하지 않는다", () => {
    expect(pollFailureBanner(0, null)).toBeNull();
    expect(pollFailureBanner(2, new Date())).toBeNull();
  });

  it("3회 연속 실패했지만 성공 이력이 없으면 시각 없이 실패만 표시한다", () => {
    expect(pollFailureBanner(3, null)).toBe("목록 갱신 실패");
  });

  it("3회 연속 실패했고 이전 성공 시각이 있으면 HH:MM을 붙인다", () => {
    const lastSuccessAt = new Date(2026, 6, 24, 9, 5);
    expect(pollFailureBanner(3, lastSuccessAt)).toBe("목록 갱신 실패 — 마지막 갱신 09:05");
  });

  it("실패가 3회를 넘어도 계속 배너를 표시한다", () => {
    const lastSuccessAt = new Date(2026, 6, 24, 23, 59);
    expect(pollFailureBanner(7, lastSuccessAt)).toBe("목록 갱신 실패 — 마지막 갱신 23:59");
  });
});
