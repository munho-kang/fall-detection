// MediaPipe PoseLandmarker 초기화와 웹캠 프레임 루프

import {
  FilesetResolver,
  PoseLandmarker,
} from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/vision_bundle.mjs";

const WASM_BASE = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/wasm";
const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";

export async function createPoseLandmarker() {
  const fileset = await FilesetResolver.forVisionTasks(WASM_BASE);
  return PoseLandmarker.createFromOptions(fileset, {
    baseOptions: { modelAssetPath: MODEL_URL, delegate: "GPU" },
    runningMode: "VIDEO",
    numPoses: 1, // 독거 전제
  });
}

export async function startCamera(video) {
  const stream = await navigator.mediaDevices.getUserMedia({
    video: { width: 640, height: 480 },
    audio: false,
  });
  video.srcObject = stream;
  await video.play();
  return stream;
}

export function runLoop(landmarker, video, onFrame) {
  let stopped = false;
  let lastVideoTime = -1;

  const tick = () => {
    if (stopped) return;
    // 같은 프레임을 두 번 넣으면 MediaPipe가 타임스탬프 역행으로 던진다
    if (video.currentTime !== lastVideoTime) {
      lastVideoTime = video.currentTime;
      const t = performance.now();
      const result = landmarker.detectForVideo(video, t);
      onFrame(result.landmarks?.[0] ?? [], t);
    }
    requestAnimationFrame(tick);
  };

  requestAnimationFrame(tick);
  return () => {
    stopped = true;
  };
}
