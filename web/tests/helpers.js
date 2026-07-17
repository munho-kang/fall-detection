// 가짜 랜드마크 시퀀스를 만들어 detector를 구동하는 테스트 헬퍼

const TORSO = 0.25; // 정규화 좌표계에서의 몸통 길이

export function poseAt({ hipY, tilt, visibility = 0.9 }) {
  const rad = (tilt * Math.PI) / 180;
  const hip = { x: 0.5, y: hipY };
  const sh = { x: hip.x + TORSO * Math.sin(rad), y: hip.y - TORSO * Math.cos(rad) };
  const lm = Array.from({ length: 33 }, () => ({ x: 0, y: 0, z: 0, visibility: 0 }));
  lm[11] = { x: sh.x - 0.1, y: sh.y, z: 0, visibility };
  lm[12] = { x: sh.x + 0.1, y: sh.y, z: 0, visibility };
  lm[23] = { x: hip.x - 0.08, y: hip.y, z: 0, visibility };
  lm[24] = { x: hip.x + 0.08, y: hip.y, z: 0, visibility };
  return lm;
}

const lerp = (a, b, p) => a + (b - a) * p;

export function segment({ startT, durationMs, from, to, fps = 30 }) {
  const step = 1000 / fps;
  const frames = [];
  for (let t = 0; t <= durationMs; t += step) {
    const p = durationMs === 0 ? 1 : t / durationMs;
    frames.push({
      t: startT + t,
      landmarks: poseAt({ hipY: lerp(from.hipY, to.hipY, p), tilt: lerp(from.tilt, to.tilt, p) }),
    });
  }
  return frames;
}

export function gap({ startT, durationMs, fps = 30 }) {
  const step = 1000 / fps;
  const frames = [];
  for (let t = 0; t <= durationMs; t += step) frames.push({ t: startT + t, landmarks: [] });
  return frames;
}

export function run(detector, frames) {
  const falls = [];
  const states = [];
  let firstFallingAt = null;
  for (const f of frames) {
    const r = detector.update(f.landmarks, f.t);
    states.push(r.state);
    if (r.state === "FALLING" && firstFallingAt === null) firstFallingAt = f.t;
    if (r.fall) falls.push(r.fall);
  }
  return { falls, states, firstFallingAt, saw: (s) => states.includes(s) };
}

export const STAND = { hipY: 0.5, tilt: 5 };
export const FLOOR = { hipY: 0.8, tilt: 80 };
export const SEATED = { hipY: 0.75, tilt: 10 };
