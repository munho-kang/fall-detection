// escalation.js 상태머신의 음성 확인→119 신고 시나리오 검증

import { describe, expect, it } from "vitest";

import { createEscalation } from "../js/escalation.js";

// t0~t1(미포함)을 100ms 간격 프레임으로 만든다. events는 { 시각: "heardOk" | "ttsEnded" }다.
function frames(t0, t1, ds, events = {}) {
  const out = [];
  for (let t = t0; t < t1; t += 100) out.push({ t, ds, event: events[t] });
  return out;
}

const standing = (t0, t1) => frames(t0, t1, "STANDING");
const fallen = (t0, t1, events) => frames(t0, t1, "FALLEN", events);
const alerted = (t0, t1, events) => frames(t0, t1, "ALERTED", events);
const noPerson = (t0, t1) => frames(t0, t1, "NO_PERSON");

function run(esc, steps) {
  const commands = [];
  const states = [];
  for (const { t, ds, event } of steps) {
    if (event) esc[event]();
    const r = esc.update(ds, t);
    for (const c of r.commands) commands.push({ t, c });
    states.push({ t, state: r.state, statusText: r.statusText });
  }
  return {
    states,
    times: (c) => commands.filter((x) => x.c === c).map((x) => x.t),
    textAt: (t) => states.find((s) => s.t === t)?.statusText,
    saw: (state) => states.some((s) => s.state === state),
  };
}

// 모든 시나리오의 에피소드 시작(FALLEN 진입)은 t=1000이다. detector가 실제로 내놓는
// 순서를 흉내 내 FALLEN 5초 뒤에는 ALERTED(보호자 알림 후)를 준다.

describe("escalation", () => {
  it("낙상 확정 0s에 MIC_ON, 10s에 PLAY_QUESTION이 정확히 1회 나간다", () => {
    const esc = createEscalation();
    const r = run(esc, [...standing(0, 1000), ...fallen(1000, 6000), ...alerted(6000, 13000)]);

    expect(r.times("MIC_ON")).toEqual([1000]);
    expect(r.times("PLAY_QUESTION")).toEqual([11000]); // 에피소드 시작 + 10초
    expect(r.textAt(1000)).toBe("대답을 듣는 중");
    expect(r.textAt(11000)).toBe("괜찮으세요? 확인 중");
    expect(esc.state).toBe("ASKING"); // ttsEnded가 아직 없다
  });

  it("무응답이면 20s에 REPORT 정확히 1회, MIC_OFF와 함께 나간다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded" }),
    ]);

    expect(r.times("REPORT")).toEqual([21000]); // 에피소드 시작 + 20초 절대 마감
    expect(r.times("MIC_OFF")).toEqual([21000]);
    expect(esc.state).toBe("REPORTED");
    expect(r.textAt(21000)).toBe("119 자동 신고됨");
  });

  it("질문 전(0~10s) '괜찮아'는 질문을 생략하고 RESOLVED — 신고 없음", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000, { 4000: "heardOk" }),
      ...alerted(6000, 26000),
    ]);

    expect(esc.state).toBe("RESOLVED");
    expect(r.times("PLAY_QUESTION")).toEqual([]); // 질문 생략
    expect(r.times("REPORT")).toEqual([]);
    expect(r.times("MIC_OFF")).toEqual([4000]);
    expect(r.textAt(4000)).toBe("응답 확인 — 신고 안 함");
  });

  it("질문 후 대기(WAITING) 중 '괜찮아'면 RESOLVED — 신고 없음", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded", 15000: "heardOk" }),
    ]);

    expect(esc.state).toBe("RESOLVED");
    expect(r.times("PLAY_QUESTION")).toEqual([11000]);
    expect(r.times("REPORT")).toEqual([]);
    expect(r.times("MIC_OFF")).toEqual([15000]);
  });

  it("어느 단계든 일어나면(STANDING) 전체 취소·MIC_OFF, 이후 아무 일도 없다", () => {
    // 청취 중 회복 — FALLEN에서 tilt가 풀리면 detector가 곧장 STANDING을 준다
    const esc1 = createEscalation();
    const r1 = run(esc1, [...standing(0, 1000), ...fallen(1000, 4000), ...standing(4000, 26000)]);
    expect(esc1.state).toBe("IDLE");
    expect(r1.times("MIC_OFF")).toEqual([4000]);
    expect(r1.times("PLAY_QUESTION")).toEqual([]);
    expect(r1.times("REPORT")).toEqual([]);
    expect(r1.textAt(4000)).toBe(null); // IDLE에서는 상태 줄을 숨긴다

    // 대답 대기 중 회복
    const esc2 = createEscalation();
    const r2 = run(esc2, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 15000, { 11500: "ttsEnded" }),
      ...standing(15000, 26000),
    ]);
    expect(esc2.state).toBe("IDLE");
    expect(r2.times("MIC_OFF")).toEqual([15000]);
    expect(r2.times("REPORT")).toEqual([]);
  });

  it("NO_PERSON(가려짐)은 회복이 아니다 — 에피소드가 유지되고 20s에 신고된다", () => {
    const esc = createEscalation();
    // ttsEnded도 영영 오지 않는 최악 경로 — 20s 절대 마감은 ASKING에서도 신고한다
    const r = run(esc, [...standing(0, 1000), ...fallen(1000, 3000), ...noPerson(3000, 26000)]);

    expect(r.times("PLAY_QUESTION")).toEqual([11000]); // 가려진 동안에도 질문은 나간다
    expect(r.times("REPORT")).toEqual([21000]);
    expect(esc.state).toBe("REPORTED");
  });

  it("신고 후 일어나기 전까지 새 에피소드가 없고, 일어나면 재무장된다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 22000, { 11500: "ttsEnded" }), // 21000에 REPORTED
      ...fallen(22000, 24000), // 누운 채 뒤척여 FALLEN이 다시 보여도
      ...standing(24000, 25000), // 일어나야만 재무장된다
      ...fallen(25000, 26000), // 새 낙상
    ]);

    expect(r.times("REPORT")).toEqual([21000]); // 누워 있는 동안 중복 신고 없음
    expect(r.times("MIC_ON")).toEqual([1000, 25000]); // 재무장 후에만 새 에피소드
    expect(esc.state).toBe("LISTENING");
  });

  it("ASKING(TTS 재생) 중 heardOk는 버린다 — 늦게 도착한 자기 목소리 인식 방어", () => {
    const esc = createEscalation();
    // 11000에 질문 시작. 11300의 heardOk는 청취 정지 직전 오디오의 늦은 인식 결과다.
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11300: "heardOk", 12000: "ttsEnded" }),
    ]);

    expect(r.saw("RESOLVED")).toBe(false); // 버려졌고, WAITING으로 넘어가서도 되살아나지 않는다
    expect(r.times("REPORT")).toEqual([21000]);
    expect(esc.state).toBe("REPORTED");
  });

  it("질문 전 '괜찮아'(RESOLVED)에 SEND_OK가 MIC_OFF와 함께 정확히 1회 나간다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000, { 4000: "heardOk" }),
      ...alerted(6000, 26000),
    ]);

    expect(r.times("SEND_OK")).toEqual([4000]);
    expect(r.times("MIC_OFF")).toEqual([4000]);
    expect(r.times("REPORT")).toEqual([]);
  });

  it("질문 후 대기 중 '괜찮아'(WAITING→RESOLVED)에도 SEND_OK가 1회 나간다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded", 15000: "heardOk" }),
    ]);

    expect(r.times("SEND_OK")).toEqual([15000]);
  });

  it("무응답 신고(REPORTED) 경로에는 SEND_OK가 없다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded" }),
    ]);

    expect(r.times("SEND_OK")).toEqual([]);
    expect(r.times("REPORT")).toEqual([21000]);
  });

  it("RESOLVED 후 재무장 전에 heardOk가 또 와도 SEND_OK는 한 번뿐이다", () => {
    const esc = createEscalation();
    // 15000에 해제된 뒤 16000의 heardOk는 늦게 도착한 STT 결과다 — 중복 전송이 없어야 한다
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded", 15000: "heardOk", 16000: "heardOk" }),
    ]);

    expect(r.times("SEND_OK")).toEqual([15000]);
  });
});
