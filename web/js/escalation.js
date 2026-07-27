// 낙상 확정 후 음성 확인→119 신고 에스컬레이션 순수 상태머신 (브라우저 API 미사용)

export const CONFIG = {
  QUESTION_AT: 10_000, // ms — 에피소드 시작(FALLEN 진입) 후 질문 재생 시점
  REPORT_AT: 20_000, // ms — 무응답 신고 마감. TTS 재생 시간과 무관한 절대 마감이다
};

// IDLE의 null은 "상태 줄을 숨겨라"다
const STATUS_TEXT = {
  IDLE: null,
  LISTENING: "🎤 음성 확인 대기",
  ASKING: "괜찮으세요? 확인 중",
  WAITING: "괜찮으세요? 확인 중",
  RESOLVED: "응답 확인 — 신고 안 함",
  REPORTED: "🚨 119 자동 신고됨",
};

export function createEscalation(config = CONFIG) {
  const c = { ...CONFIG, ...config };

  let state = "IDLE";
  let startedAt = null;
  let heardOkPending = false;
  let ttsEndedPending = false;

  const inEpisode = () => state === "LISTENING" || state === "ASKING" || state === "WAITING";

  function update(detectorState, t) {
    const commands = [];
    const heardOk = heardOkPending;
    const ttsEnded = ttsEndedPending;
    // ASKING이 소비 없이 버리는 것까지 포함해, 이벤트는 어느 상태에서든 한 프레임만 산다
    heardOkPending = false;
    ttsEndedPending = false;

    if (inEpisode() && detectorState === "STANDING") {
      // 일어났다 — 어느 단계든 전체 취소다. NO_PERSON은 여기 오지 않으므로 에피소드가 유지된다.
      state = "IDLE";
      commands.push("MIC_OFF");
    } else {
      switch (state) {
        case "IDLE":
          // 종결 뒤라면 STANDING(재무장)을 거쳐서만 돌아오므로, FALLEN이 보이면 곧 새 에피소드다
          if (detectorState === "FALLEN") {
            state = "LISTENING";
            startedAt = t;
            commands.push("MIC_ON");
          }
          break;

        case "LISTENING":
          if (heardOk) {
            state = "RESOLVED"; // 질문(10s) 전이면 질문도 생략된다
            commands.push("MIC_OFF");
          } else if (t - startedAt >= c.QUESTION_AT) {
            state = "ASKING";
            commands.push("PLAY_QUESTION");
          }
          break;

        case "ASKING":
          // heardOk는 버린다 — 어댑터가 청취를 꺼두지만, 정지 직전 오디오의 늦은 인식 결과가
          // 자기 질문("괜찮으세요?")일 수 있어 상태머신 차원에서도 이중으로 방어한다.
          if (t - startedAt >= c.REPORT_AT) {
            state = "REPORTED"; // ttsEnded가 영영 안 와도 절대 마감이 신고한다
            commands.push("REPORT", "MIC_OFF");
          } else if (ttsEnded) {
            state = "WAITING"; // TTS 실패·스킵도 같은 경로 — 어댑터가 즉시 ttsEnded를 넣는다
          }
          break;

        case "WAITING":
          // 마감 프레임에 함께 도착한 heardOk는 응답으로 인정한다 — 대답은 마감 전에 나왔다
          if (heardOk) {
            state = "RESOLVED";
            commands.push("MIC_OFF");
          } else if (t - startedAt >= c.REPORT_AT) {
            state = "REPORTED";
            commands.push("REPORT", "MIC_OFF");
          }
          break;

        case "RESOLVED":
        case "REPORTED":
          // 일어나야만 재무장된다 — 누워 있는 동안 중복 신고가 없는 이유다 (ALERTED 재무장과 같은 규칙)
          if (detectorState === "STANDING") state = "IDLE";
          break;
      }
    }

    return { state, commands, statusText: STATUS_TEXT[state] };
  }

  return {
    update,
    heardOk() {
      heardOkPending = true;
    },
    ttsEnded() {
      ttsEndedPending = true;
    },
    get state() {
      return state;
    },
  };
}
