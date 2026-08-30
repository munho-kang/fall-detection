// 감지 페이지 조립 — 방 선택 → 웹캠 → MediaPipe → 상태머신 → 화면

import { listRooms, postFall, requireToken } from "./api.js";
import { createDetector } from "./detector.js";
import { createEscalation } from "./escalation.js";
import { drawSkeleton } from "./overlay.js";
import { createPoseLandmarker, runLoop, startCamera } from "./pose.js";
import { createFallQueue } from "./queue.js";
import { createSpeechAdapter } from "./speech.js";
import { createTuningRecorder } from "./tuning.js";
import { createView } from "./view.js";

requireToken();

const el = Object.fromEntries(
  [
    "setup", "stageWrap", "start", "error", "banner", "roomSelect", "noRooms",
    "room", "clock", "verdict", "verdictSub", "gate1", "gate2", "gate3",
    "escalation", "escalationStatus", "countdown", "step1", "step2", "step3",
    "sent", "video", "canvas", "peak", "download",
  ].map((id) => [id, document.getElementById(id)]),
);

function showBanner(message) {
  el.banner.textContent = message;
  el.banner.classList.remove("hidden");
}

const ctx = el.canvas.getContext("2d");
const detector = createDetector();
const tuning = createTuningRecorder({ peakEl: el.peak, downloadEl: el.download });
const view = createView(el);
let sentCount = 0;

const escalation = createEscalation();
const speech = createSpeechAdapter({
  onHeardOk: () => escalation.heardOk(),
  onTtsEnded: () => escalation.ttsEnded(),
});
let lastFallPayload = null; // 현재 에피소드에서 확정 전송한 낙상 — 신고 재-POST의 바탕
let lastFallingAt = null; // 마지막 FALLING 진입 시각 — 확정 전에 가려진 채 신고에 이르는 드문 경로용
let pendingVoiceOkAt = null; // 이 에피소드의 "괜찮아" 응답 시각 — 원본 전송 전이면 5s 원본에 동승한다
let prevDetectorState = null;
let fallenAt = null; // 세 번째 관문(5초 유지)의 진행 막대를 그리는 데 쓴다

const queue = createFallQueue(localStorage);
// flush 개별 항목은 1회만 시도한다 — 실패하면 어차피 다음 트리거가 다시 부른다
const flushQueue = () => queue.flush((payload) => postFall(payload, 1));

flushQueue(); // 페이지 로드 시
window.addEventListener("online", flushQueue);
setInterval(flushQueue, 60_000);

let rooms = [];

// 방 추가·수정·삭제는 보호자 앱의 방 관리에서만 한다 — 이 페이지는 목록을 읽어 고르기만 한다
async function refreshRooms() {
  rooms = await listRooms();
  el.roomSelect.innerHTML = "";
  for (const room of rooms) {
    const opt = document.createElement("option");
    opt.value = String(room.id);
    opt.textContent = `${room.name} ${room.number}`;
    el.roomSelect.append(opt);
  }
  const empty = rooms.length === 0;
  el.noRooms.classList.toggle("hidden", !empty);
  el.start.disabled = empty; // 방 없이는 감지를 시작할 수 없다
}

refreshRooms().catch((err) => {
  el.error.textContent = err.message;
});

el.start.addEventListener("click", async () => {
  el.error.textContent = "";

  const selected = rooms.find((r) => String(r.id) === el.roomSelect.value);
  if (!selected) {
    el.error.textContent = "방을 먼저 선택하세요.";
    return;
  }
  const room = { name: selected.name, number: selected.number };

  el.start.disabled = true;

  let landmarker;
  try {
    landmarker = await createPoseLandmarker();
  } catch (err) {
    el.error.textContent = `모델을 불러오지 못했습니다. 네트워크를 확인하고 새로고침하세요. (${err.message})`;
    el.start.disabled = false;
    return;
  }

  try {
    await startCamera(el.video);
  } catch (err) {
    el.error.textContent = `웹캠을 사용할 수 없습니다. 브라우저 주소창의 카메라 권한을 허용한 뒤 다시 시도하세요. (${err.name})`;
    el.start.disabled = false;
    return;
  }

  // 응급 순간에 권한 팝업이 뜨면 안 된다 — 카메라에 이어 미리 받아 두고 트랙은 바로 끈다.
  // 거부해도 감지는 그대로 진행한다. STT가 영영 못 들으면 무응답과 같아 20초에 신고가 나간다.
  await speech.requestMicPermission();

  el.room.textContent = `${room.name} ${room.number}`;
  el.setup.classList.add("hidden");
  el.stageWrap.classList.remove("hidden");

  // 상단 바 시계 — 시연 녹화에 사고 시각이 함께 남는다
  const tick = () => {
    el.clock.textContent = new Date().toLocaleTimeString("ko-KR", { hour12: false });
  };
  tick();
  setInterval(tick, 1000);

  // 20s 무응답 — 같은 낙상 payload에 신고 시각만 붙여 한 번 더 보낸다. 서버가 기존 행에 병합한다.
  const reportEmergency = (t) => {
    // 확정(5s) 전부터 계속 가려져 원본 전송이 아직 없는 드문 경로에서도 신고는 나가야 한다.
    // occurred_at을 원본과 같게 맞춰야 나중에 원본이 도착해도 서버가 한 행으로 합친다.
    const base = lastFallPayload ?? {
      room_name: room.name,
      room_number: room.number,
      occurred_at: new Date(performance.timeOrigin + lastFallingAt).toISOString(),
      confidence: 0,
    };
    const payload = { ...base, reported_119_at: new Date(performance.timeOrigin + t).toISOString() };
    postFall(payload)
      .then(() => flushQueue())
      .catch(() => {
        // 신고도 같은 큐를 탄다 — 연결이 돌아오면 재전송되고 서버가 병합한다
        queue.enqueue(payload);
        showBanner("전송 실패 — 저장해 두었다가 연결되면 다시 보냅니다");
      });
  };

  // "괜찮아" 응답 — 원본이 이미 나갔으면 같은 payload에 응답 시각만 붙여 한 번 더 보낸다.
  // 원본 전송 전(5초 이전 조기 응답)이면 시각만 들고 있다가 원본 payload에 동승시킨다 —
  // 즉시 POST하면 "5초 내 회복 = 기록 없음" 동작이 깨진다.
  const sendVoiceOk = (t) => {
    pendingVoiceOkAt = t;
    if (!lastFallPayload) return; // 원본 미전송 — 확정(5s) 시 payload에 실려 나간다
    const payload = {
      ...lastFallPayload,
      voice_ok_at: new Date(performance.timeOrigin + t).toISOString(),
    };
    postFall(payload)
      .then(() => flushQueue())
      .catch(() => {
        // 응답 기록도 같은 큐를 탄다 — 연결이 돌아오면 재전송되고 서버가 병합한다
        queue.enqueue(payload);
        showBanner("전송 실패 — 저장해 두었다가 연결되면 다시 보냅니다");
      });
  };

  runLoop(landmarker, el.video, (landmarks, t) => {
    const { state, fall, tilt, hipVelocity } = detector.update(landmarks, t);

    // 확정(5s) 전에 신고 마감이 오는 드문 경로를 위해, 실제로 넘어진 시각을 따로 기억한다
    if (state === "FALLING" && prevDetectorState !== "FALLING") lastFallingAt = t;
    if (state === "FALLEN" || state === "ALERTED") fallenAt ??= t;
    else fallenAt = null;
    prevDetectorState = state;

    drawSkeleton(ctx, landmarks, state);
    view.frame({ state, tilt, hipVelocity, fallenFor: fallenAt == null ? 0 : t - fallenAt });
    tuning.record(t, state, tilt, hipVelocity);

    if (fall) {
      const payload = {
        room_name: room.name,
        room_number: room.number,
        occurred_at: new Date(performance.timeOrigin + fall.occurredAt).toISOString(),
        confidence: fall.confidence,
        // 5초 전에 이미 "괜찮아"가 나온 에피소드 — 응답 시각이 원본에 동승한다
        ...(pendingVoiceOkAt != null
          ? { voice_ok_at: new Date(performance.timeOrigin + pendingVoiceOkAt).toISOString() }
          : {}),
      };
      lastFallPayload = payload; // 이 에피소드의 신고 재-POST가 이 payload를 바탕으로 삼는다
      postFall(payload)
        .then(() => {
          sentCount += 1;
          el.sent.textContent = `전송된 낙상 ${sentCount}건`;
          flushQueue(); // 방금 성공했으니 밀려 있던 것도 지금 보낸다
        })
        .catch(() => {
          // 401 로그아웃 중이어도 적재해 둔다 — 재로그인 후 flush가 되살리므로 손해가 없다
          queue.enqueue(payload);
          showBanner("전송 실패 — 저장해 두었다가 연결되면 다시 보냅니다");
        });
    }

    // 같은 틱에 fall 확정과 SEND_OK가 겹치면 위 원본은 voice_ok 없이 나가고 재-POST가 뒤따른다(2회 POST) — 서버 병합이 멱등이라 결과는 같다.
    const esc = escalation.update(state, t);
    view.escalation(esc);
    for (const command of esc.commands) {
      if (command === "MIC_ON") {
        lastFallPayload = null; // 새 에피소드 — 이전 낙상의 payload가 신고에 섞이면 안 된다
        pendingVoiceOkAt = null; // 이전 에피소드의 응답 시각도 함께 버린다
        speech.startListening();
      } else if (command === "PLAY_QUESTION") {
        speech.playQuestion();
      } else if (command === "REPORT") {
        reportEmergency(t);
      } else if (command === "SEND_OK") {
        sendVoiceOk(t);
      } else if (command === "MIC_OFF") {
        speech.stopListening();
      }
    }
  });
});
