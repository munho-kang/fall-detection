// 랜드마크 시퀀스로 낙상을 판정하는 순수 상태머신 (브라우저 API 미사용)

export const CONFIG = {
  FALL_VELOCITY: 0.45, // 정규화 y단위/초 — 이 위면 낙하 중
  TILT_UPRIGHT: 45, // ° — 이 아래면 서 있음
  TILT_FALLEN: 60, // ° — 이 위면 수평
  FALLING_WINDOW: 1000, // ms — FALLING 유효 시간
  FALLEN_HOLD: 5000, // ms — 미회복 확정 시간
  EMA_ALPHA: 0.4,
  NO_PERSON_TIMEOUT: 2000, // ms — 이만큼 미검출이면 NO_PERSON
};

export const LM = { L_SHOULDER: 11, R_SHOULDER: 12, L_HIP: 23, R_HIP: 24 };

const REQUIRED = [LM.L_SHOULDER, LM.R_SHOULDER, LM.L_HIP, LM.R_HIP];

const mid = (a, b) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });

function hasRequired(landmarks) {
  if (!landmarks || landmarks.length === 0) return false;
  return REQUIRED.every((i) => landmarks[i] != null);
}

export function createDetector(config = CONFIG) {
  const c = { ...CONFIG, ...config };

  let state = "NO_PERSON";
  let tilt = null;
  let hipVelocity = 0;
  let prevHip = null;
  let prevT = null;
  let lastSeenAt = null;
  let fallingAt = null;
  let fallenAt = null;

  // 설계에 명시된 심층 방어다. 다만 오탐지를 실제로 막는 것은 아래 Δt 계산이지
  // 이 초기화가 아니다 — NO_PERSON은 2초 이상 미검출일 때만 발동하므로
  // 복귀 시 Δt가 항상 2000ms 이상이고 가짜 속도는 임계값에 못 미친다.
  const resetMotion = () => {
    tilt = null;
    hipVelocity = 0;
    prevHip = null;
    prevT = null;
  };

  const ema = (prev, raw) => (prev === null ? raw : c.EMA_ALPHA * raw + (1 - c.EMA_ALPHA) * prev);

  function update(landmarks, t) {
    if (!hasRequired(landmarks)) {
      if (lastSeenAt === null || t - lastSeenAt > c.NO_PERSON_TIMEOUT) {
        state = "NO_PERSON";
        resetMotion();
      }
      // 미검출 유예 구간에서는 판정할 지표가 없으므로 상태를 유지한다
      return { state, fall: null, tilt, hipVelocity };
    }

    lastSeenAt = t;
    const shoulderMid = mid(landmarks[LM.L_SHOULDER], landmarks[LM.R_SHOULDER]);
    const hipMid = mid(landmarks[LM.L_HIP], landmarks[LM.R_HIP]);

    const dx = shoulderMid.x - hipMid.x;
    const dy = shoulderMid.y - hipMid.y;
    tilt = ema(tilt, (Math.atan2(Math.abs(dx), Math.abs(dy)) * 180) / Math.PI);

    // Δt는 반드시 실제 타임스탬프 차이다. 고정 프레임 간격을 가정하면
    // 미검출 복귀 시 좌표 점프가 임계값의 20배짜리 가짜 속도로 잡힌다.
    let rawVelocity = 0;
    if (prevHip !== null && t > prevT) {
      rawVelocity = (hipMid.y - prevHip.y) / ((t - prevT) / 1000);
    }
    hipVelocity = ema(hipVelocity, rawVelocity);
    prevHip = hipMid;
    prevT = t;

    let fall = null;

    // 위에서부터 평가하고 처음 일치하는 규칙 하나만 적용한다
    switch (state) {
      case "NO_PERSON":
        state = "STANDING";
        break;

      case "STANDING":
        if (hipVelocity > c.FALL_VELOCITY) {
          state = "FALLING"; // 1차 관문: 속도 — 천천히 눕기를 거른다
          fallingAt = t;
        }
        break;

      case "FALLING":
        if (tilt > c.TILT_FALLEN) {
          state = "FALLEN"; // 2차 관문: 자세 — 급히 앉기를 거른다
          fallenAt = t;
        } else if (t - fallingAt > c.FALLING_WINDOW) {
          state = "STANDING";
        }
        break;

      case "FALLEN":
        if (tilt < c.TILT_UPRIGHT) {
          state = "STANDING"; // 오탐지 취소, 전송 안 함
        } else if (t - fallenAt > c.FALLEN_HOLD) {
          state = "ALERTED"; // 3차 관문: 시간 — 자가 회복을 거른다
          fall = {
            occurredAt: fallingAt, // 확정 시각이 아니라 실제로 넘어진 순간
            confidence:
              REQUIRED.reduce((s, i) => s + (landmarks[i].visibility ?? 0), 0) / REQUIRED.length,
          };
        }
        break;

      case "ALERTED":
        // 다시 일어나야만 재무장된다. 누워 있는 동안 중복 전송이 없는 이유다.
        if (tilt < c.TILT_UPRIGHT) state = "STANDING";
        break;
    }

    return { state, fall, tilt, hipVelocity };
  }

  return {
    update,
    get state() {
      return state;
    },
  };
}
