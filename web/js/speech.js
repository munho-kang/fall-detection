// 음성 어댑터 — TTS 질문 재생과 STT("괜찮") 인식. 자기 목소리 방어와 자동 재시작을 맡는다.

const QUESTION = "괜찮으세요?";
const OK_KEYWORD = "괜찮"; // "괜찮아", "괜찮아요", "나 괜찮아" 전부 걸린다

export function createSpeechAdapter({ onHeardOk, onTtsEnded }) {
  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  let recognition = null; // 살아 있는 인식 세션 (없으면 null)
  let listening = false; // 에피소드 동안 true — onend 자동 재시작의 근거
  let paused = false; // TTS 재생 동안 true — 자기 질문을 알아듣지 않게 청취를 끈다

  function startRecognition() {
    if (!SR || recognition || !listening || paused) return;
    const r = new SR();
    r.lang = "ko-KR";
    r.continuous = true;
    r.interimResults = true; // 중간 결과에서 "괜찮"이 잡혀도 바로 해제한다
    r.onresult = (e) => {
      for (let i = e.resultIndex; i < e.results.length; i += 1) {
        if (e.results[i][0].transcript.includes(OK_KEYWORD)) {
          onHeardOk();
          return;
        }
      }
    };
    r.onend = () => {
      // 침묵·일시 오류로 끊겨도 에피소드가 살아 있으면 다시 듣는다.
      // 마이크 거부처럼 시작이 계속 실패해도 그냥 조용하다 — 무응답과 같아 20초에 신고가 나간다.
      recognition = null;
      startRecognition();
    };
    recognition = r;
    try {
      r.start();
    } catch {
      recognition = null;
    }
  }

  function stopRecognition() {
    if (!recognition) return;
    const r = recognition;
    recognition = null;
    r.onend = null; // 의도한 정지는 자동 재시작하지 않는다
    try {
      r.stop();
    } catch {
      // 이미 죽어 있어도 상관없다
    }
  }

  return {
    // 감지 시작 클릭 때 카메라와 함께 미리 받아 둔다 — 응급 순간에 권한 팝업이 뜨면 안 된다.
    // 받자마자 트랙을 꺼서 평상시에는 마이크가 완전히 꺼져 있게 한다.
    async requestMicPermission() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        for (const track of stream.getTracks()) track.stop();
      } catch {
        // 거부·미지원은 무응답과 같다 — 확인 실패가 신고를 삼키지 않는다
      }
    },

    startListening() {
      listening = true;
      paused = false;
      startRecognition();
    },

    stopListening() {
      listening = false;
      paused = false;
      stopRecognition();
    },

    // 질문 재생. 시작 전에 청취를 멈추고 끝난 뒤 재개한다 — 질문 "괜찮으세요?"에도
    // "괜찮"이 들어 있어, 켜 둔 채 재생하면 시스템이 자기 질문을 알아듣고 신고를 취소한다.
    playQuestion() {
      paused = true;
      stopRecognition();
      let finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        paused = false;
        startRecognition(); // 에피소드가 이미 끝났으면(listening=false) 안에서 무시된다
        onTtsEnded();
      };
      if (!window.speechSynthesis || typeof SpeechSynthesisUtterance === "undefined") {
        finish(); // TTS 미지원 — 질문을 생략하고 바로 대답 대기로 넘어간다
        return;
      }
      const utterance = new SpeechSynthesisUtterance(QUESTION);
      utterance.lang = "ko-KR";
      utterance.onend = finish;
      utterance.onerror = finish;
      speechSynthesis.speak(utterance);
    },
  };
}
