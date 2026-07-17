// detector.js 상태머신의 7개 낙상 시나리오 검증

import { describe, it, expect } from "vitest";

import { createDetector } from "../js/detector.js";
import { segment, gap, run, STAND, FLOOR, SEATED } from "./helpers.js";

const standing = (startT, durationMs) => segment({ startT, durationMs, from: STAND, to: STAND });
const holdFloor = (startT, durationMs) => segment({ startT, durationMs, from: FLOOR, to: FLOOR });
const fastFall = (startT) => segment({ startT, durationMs: 300, from: STAND, to: FLOOR });
const getUp = (startT) => segment({ startT, durationMs: 500, from: FLOOR, to: STAND });

describe("detector", () => {
  it("천천히 눕기 → 알림 없음 (FALLING 미진입)", () => {
    const frames = [
      ...standing(0, 1000),
      ...segment({ startT: 1000, durationMs: 4000, from: STAND, to: FLOOR }),
      ...holdFloor(5000, 8000),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLING")).toBe(false); // 1차 관문에서 걸러진다
  });

  it("빠르게 주저앉기 → 알림 없음 (tilt 미달)", () => {
    const frames = [
      ...standing(0, 1000),
      ...segment({ startT: 1000, durationMs: 300, from: STAND, to: SEATED }),
      ...segment({ startT: 1300, durationMs: 3000, from: SEATED, to: SEATED }),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLING")).toBe(true); // 속도는 넘었지만
    expect(r.saw("FALLEN")).toBe(false); // 2차 관문에서 걸러진다
  });

  it("빠르게 넘어져 3초 만에 일어남 → 알림 없음 (자가 회복)", () => {
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 3000),
      ...getUp(4300),
      ...standing(4800, 2000),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLEN")).toBe(true); // 넘어진 것은 맞지만
    expect(r.saw("ALERTED")).toBe(false); // 3차 관문에서 걸러진다
  });

  it("빠르게 넘어져 5초 유지 → 낙상 1건, occurred_at은 FALLING 진입 시각", () => {
    const frames = [...standing(0, 1000), ...fastFall(1000), ...holdFloor(1300, 6700)];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
    expect(r.falls[0].occurredAt).toBe(r.firstFallingAt);
    expect(r.falls[0].occurredAt).toBeLessThan(1400); // 확정 시각(~6250)이 아니라 넘어진 시각이다
    expect(r.falls[0].confidence).toBeCloseTo(0.9, 5);
  });

  it("넘어진 채 10초 더 유지 → 여전히 1건 (중복 없음)", () => {
    const frames = [...standing(0, 1000), ...fastFall(1000), ...holdFloor(1300, 16700)];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
  });

  it("넘어졌다 일어났다 다시 넘어짐 → 2건", () => {
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 6700),
      ...getUp(8000), // ALERTED → STANDING 재무장
      ...standing(8500, 1500),
      ...fastFall(10000),
      ...holdFloor(10300, 6700),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(2);
  });

  it("2초 이상 미검출 후 바닥에서 재검출 → NO_PERSON을 거쳐 오탐지 없음", () => {
    const frames = [
      ...standing(0, 1000),
      ...gap({ startT: 1033, durationMs: 3000 }),
      ...segment({ startT: 4033, durationMs: 2000, from: FLOOR, to: FLOOR }),
    ];
    const r = run(createDetector(), frames);

    expect(r.saw("NO_PERSON")).toBe(true);
    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLING")).toBe(false); // 재검출 시 좌표 점프가 가짜 속도로 잡히면 안 된다
  });
});
