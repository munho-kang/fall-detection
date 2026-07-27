// 감지 페이지 조립 — 방 선택 → 웹캠 → MediaPipe → 상태머신 → 화면

import { createRoom, listRooms, postFall, requireToken } from "./api.js";
import { createDetector } from "./detector.js";
import { createEscalation } from "./escalation.js";
import { drawSkeleton } from "./overlay.js";
import { createPoseLandmarker, runLoop, startCamera } from "./pose.js";
import { createFallQueue } from "./queue.js";
import { createSpeechAdapter } from "./speech.js";
import { createTuningRecorder } from "./tuning.js";

requireToken();

const el = {
  setup: document.getElementById("setup"),
  stage: document.getElementById("stage"),
  start: document.getElementById("start"),
  error: document.getElementById("error"),
  banner: document.getElementById("banner"),
  roomSelect: document.getElementById("roomSelect"),
  noRooms: document.getElementById("noRooms"),
  addRoom: document.getElementById("addRoom"),
  newRoomName: document.getElementById("newRoomName"),
  newRoomNumber: document.getElementById("newRoomNumber"),
  addRoomBtn: document.getElementById("addRoomBtn"),
  room: document.getElementById("room"),
  state: document.getElementById("state"),
  metrics: document.getElementById("metrics"),
  escalation: document.getElementById("escalation"),
  sent: document.getElementById("sent"),
  video: document.getElementById("video"),
  canvas: document.getElementById("canvas"),
  peak: document.getElementById("peak"),
  download: document.getElementById("download"),
};

function showBanner(message) {
  el.banner.textContent = message;
  el.banner.classList.remove("hidden");
}

const ctx = el.canvas.getContext("2d");
const detector = createDetector();
const tuning = createTuningRecorder({ peakEl: el.peak, downloadEl: el.download });
let sentCount = 0;

const escalation = createEscalation();
const speech = createSpeechAdapter({
  onHeardOk: () => escalation.heardOk(),
  onTtsEnded: () => escalation.ttsEnded(),
});
let lastFallPayload = null; // 현재 에피소드에서 확정 전송한 낙상 — 신고 재-POST의 바탕
let lastFallingAt = null; // 마지막 FALLING 진입 시각 — 확정 전에 가려진 채 신고에 이르는 드문 경로용
let prevDetectorState = null;

const queue = createFallQueue(localStorage);
// flush 개별 항목은 1회만 시도한다 — 실패하면 어차피 다음 트리거가 다시 부른다
const flushQueue = () => queue.flush((payload) => postFall(payload, 1));

flushQueue(); // 페이지 로드 시
window.addEventListener("online", flushQueue);
setInterval(flushQueue, 60_000);

let rooms = [];

async function refreshRooms(selectId) {
  rooms = await listRooms();
  el.roomSelect.innerHTML = "";
  for (const room of rooms) {
    const opt = document.createElement("option");
    opt.value = String(room.id);
    opt.textContent = `${room.name} ${room.number}`;
    el.roomSelect.append(opt);
  }
  if (selectId != null) el.roomSelect.value = String(selectId);
  const empty = rooms.length === 0;
  el.noRooms.classList.toggle("hidden", !empty);
  el.start.disabled = empty; // 방 없이는 감지를 시작할 수 없다
  if (empty) el.addRoom.open = true; // 설치 흐름이 안 끊기게 추가 폼을 바로 펼친다
}

refreshRooms().catch((err) => {
  el.error.textContent = err.message;
});

el.addRoomBtn.addEventListener("click", async () => {
  el.error.textContent = "";
  try {
    const room = await createRoom(el.newRoomName.value.trim(), Number(el.newRoomNumber.value));
    el.newRoomName.value = "";
    await refreshRooms(room.id); // 방금 만든 방을 선택해 둔다
  } catch (err) {
    el.error.textContent = err.message;
  }
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
  el.stage.classList.remove("hidden");

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

  runLoop(landmarker, el.video, (landmarks, t) => {
    const { state, fall, tilt, hipVelocity } = detector.update(landmarks, t);

    // 확정(5s) 전에 신고 마감이 오는 드문 경로를 위해, 실제로 넘어진 시각을 따로 기억한다
    if (state === "FALLING" && prevDetectorState !== "FALLING") lastFallingAt = t;
    prevDetectorState = state;

    drawSkeleton(ctx, landmarks, state);
    el.state.textContent = state;
    el.metrics.textContent = `tilt ${(tilt ?? 0).toFixed(1)}°  ·  hipV ${hipVelocity.toFixed(2)}/s`;
    tuning.record(t, state, tilt, hipVelocity);

    if (fall) {
      const payload = {
        room_name: room.name,
        room_number: room.number,
        occurred_at: new Date(performance.timeOrigin + fall.occurredAt).toISOString(),
        confidence: fall.confidence,
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

    const esc = escalation.update(state, t);
    el.escalation.textContent = esc.statusText ?? "";
    el.escalation.classList.toggle("hidden", !esc.statusText);
    for (const command of esc.commands) {
      if (command === "MIC_ON") {
        lastFallPayload = null; // 새 에피소드 — 이전 낙상의 payload가 신고에 섞이면 안 된다
        speech.startListening();
      } else if (command === "PLAY_QUESTION") {
        speech.playQuestion();
      } else if (command === "REPORT") {
        reportEmergency(t);
      } else if (command === "MIC_OFF") {
        speech.stopListening();
      }
    }
  });
});
