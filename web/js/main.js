// 감지 페이지 조립 — 방 선택 → 웹캠 → MediaPipe → 상태머신 → 화면

import { requireToken } from "./api.js";
import { createDetector } from "./detector.js";
import { drawSkeleton } from "./overlay.js";
import { createPoseLandmarker, runLoop, startCamera } from "./pose.js";

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
};

const ctx = el.canvas.getContext("2d");
const detector = createDetector();
let sentCount = 0;

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

    if (fall) {
      sentCount += 1;
      el.sent.textContent = `전송된 낙상 ${sentCount}건`;
      console.log("낙상 확정", { room, fall });
    }
  });
});
