// detector.js 상태머신의 낙상 시나리오 검증

import { describe, it, expect } from "vitest";

import { createDetector } from "../js/detector.js";
import { segment, run, STAND, FLOOR } from "./helpers.js";

const standing = (startT, durationMs) => segment({ startT, durationMs, from: STAND, to: STAND });
const holdFloor = (startT, durationMs) => segment({ startT, durationMs, from: FLOOR, to: FLOOR });
const fastFall = (startT) => segment({ startT, durationMs: 300, from: STAND, to: FLOOR });

describe("detector", () => {
  it("빠르게 넘어져 5초 유지 → 낙상 1건, occurred_at은 FALLING 진입 시각", () => {
    const frames = [...standing(0, 1000), ...fastFall(1000), ...holdFloor(1300, 6700)];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
    expect(r.falls[0].occurredAt).toBe(r.firstFallingAt);
    expect(r.falls[0].occurredAt).toBeLessThan(1400); // 확정 시각(~6250)이 아니라 넘어진 시각이다
    expect(r.falls[0].confidence).toBeCloseTo(0.9, 5);
  });
});
