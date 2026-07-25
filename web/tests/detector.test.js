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

  it("낙상 후 2.5초 미검출 → 재검출해도 낙상 1건, occurred_at은 원래 FALLING 진입 시각", () => {
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 1500),
      ...gap({ startT: 2800, durationMs: 2500 }),
      ...holdFloor(5300, 8000),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
    expect(r.falls[0].occurredAt).toBe(r.firstFallingAt);
  });

  it("낙상 도중(FALLING) 2.5초 미검출 → 바닥에서 재검출해도 낙상 1건", () => {
    const frames = [
      ...standing(0, 1000),
      ...segment({ startT: 1000, durationMs: 150, from: STAND, to: { hipY: 0.65, tilt: 40 } }),
      ...gap({ startT: 1150, durationMs: 2500 }),
      ...holdFloor(3650, 8000),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
  });

  it("알림 후 2.5초 미검출 → 바닥에서 재검출되면 ALERTED가 유지된다 (재무장 안 됨)", () => {
    // ALERTED의 불변식은 "다시 일어나야만 재무장된다"다. 넘어진 사람이 가구에 가려
    // 끊겼다가 여전히 누운 채 재검출된 것은 일어난 것이 아니므로 재무장해선 안 된다.
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 6700), // ALERTED 확정 (알림 1건)
      ...gap({ startT: 8000, durationMs: 2500 }),
      ...holdFloor(10500, 2000), // 여전히 바닥에 누운 채 재검출
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
    const noPersonEndIdx = r.states.lastIndexOf("NO_PERSON");
    expect(r.states[noPersonEndIdx + 1]).toBe("ALERTED"); // STANDING이면 재무장된 것이다
    expect(r.states.at(-1)).toBe("ALERTED");
  });

  it("알림 후 미검출 → 바닥 재검출 → 누운 채 뒤척임 → 여전히 1건 (같은 낙상 중복 전송 없음)", () => {
    // 재무장되면 이미 수평이라 2차 관문이 한 프레임에 열려 같은 낙상이 두 번 전송된다.
    // 서버 dedup 키는 occurred_at이고 두 번째 fallingAt은 다른 값이라 흡수되지 않는다.
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 6700),
      ...gap({ startT: 8000, durationMs: 2500 }),
      ...holdFloor(10500, 500),
      // 누운 채(tilt 80°) 몸을 크게 뒤척여 hipVelocity가 임계값을 넘게 만든다
      ...segment({ startT: 11000, durationMs: 100, from: FLOOR, to: { hipY: 0.6, tilt: 80 } }),
      ...segment({ startT: 11100, durationMs: 100, from: { hipY: 0.6, tilt: 80 }, to: FLOOR }),
      ...holdFloor(11200, 6700),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
  });

  it("낙상 후 2.5초 미검출 → 일어선 채 재검출되면 낙상 0건 (위 두 건과 반대: 갇힌 회복)", () => {
    // 위 두 건은 끊김 뒤에도 바닥에 누워 있어 FALLEN이 복원되고 알림이 울린다.
    // 이 건은 그 거울상이다 — 끊긴 동안 스스로 일어났으므로 tilt 관문이 복원을 막아야 한다.
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 1500),
      ...gap({ startT: 2800, durationMs: 2500 }),
      ...standing(5300, 8000), // 재검출 시 이미 서 있다 (STAND, FLOOR 아님)
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLEN")).toBe(true); // 끊기기 전엔 분명 넘어져 있었지만

    // tilt 관문이 없다면 재검출 직후 한 프레임 동안 FALLEN으로 잘못 복원된다.
    // NO_PERSON 구간이 끝난 바로 다음 상태가 곧장 STANDING이어야 한다.
    const noPersonEndIdx = r.states.lastIndexOf("NO_PERSON");
    expect(r.states[noPersonEndIdx + 1]).toBe("STANDING");
    expect(r.states.at(-1)).toBe("STANDING");
  });
});
