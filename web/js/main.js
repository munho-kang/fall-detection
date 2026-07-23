// 감지 페이지 조립 — 방 선택 → 웹캠 → MediaPipe → 상태머신 → 화면

import { postFall, requireToken } from "./api.js";
import { createDetector } from "./detector.js";
import { drawSkeleton } from "./overlay.js";
import { createPoseLandmarker, runLoop, startCamera } from "./pose.js";
import { createFallQueue } from "./queue.js";
import { createTuningRecorder } from "./tuning.js";

requireToken();

const el = {
  setup: document.getElementById("setup"),
  stage: document.getElementById("stage"),
  start: document.getElementById("start"),
  error: document.getElementById("error"),
  banner: document.getElementById("banner"),
  roomName: document.getElementById("roomName"),
  roomNumber: document.getElementById("roomNumber"),
  room: document.getElementById("room"),
  state: document.getElementById("state"),
  metrics: document.getElementById("metrics"),
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

const queue = createFallQueue(localStorage);
// flush 개별 항목은 1회만 시도한다 — 실패하면 어차피 다음 트리거가 다시 부른다
const flushQueue = () => queue.flush((payload) => postFall(payload, 1));

flushQueue(); // 페이지 로드 시
window.addEventListener("online", flushQueue);
setInterval(flushQueue, 60_000);

el.start.addEventListener("click", async () => {
  el.error.textContent = "";
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

  const room = { name: el.roomName.value, number: Number(el.roomNumber.value) };
  el.room.textContent = `${room.name} ${room.number}`;
  el.setup.classList.add("hidden");
  el.stage.classList.remove("hidden");

  runLoop(landmarker, el.video, (landmarks, t) => {
    const { state, fall, tilt, hipVelocity } = detector.update(landmarks, t);

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
  });
});
