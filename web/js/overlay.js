// 검은 배경 위에 스켈레톤만 그린다 (원본 영상은 절대 그리지 않는다)

const CONNECTIONS = [
  [11, 12], // 어깨
  [11, 23],
  [12, 24], // 몸통
  [23, 24], // 골반
  [11, 13],
  [13, 15], // 왼팔
  [12, 14],
  [14, 16], // 오른팔
  [23, 25],
  [25, 27], // 왼다리
  [24, 26],
  [26, 28], // 오른다리
];

const STATE_COLOR = {
  NO_PERSON: "#8b93a7",
  STANDING: "#4c8dff",
  FALLING: "#f5a524",
  FALLEN: "#f5a524",
  ALERTED: "#e5484d",
};

export function drawSkeleton(ctx, landmarks, state) {
  const { width, height } = ctx.canvas;

  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, width, height);

  if (!landmarks || landmarks.length === 0) return;

  const color = STATE_COLOR[state] ?? "#8b93a7";
  const px = (lm) => [lm.x * width, lm.y * height];

  ctx.strokeStyle = color;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  for (const [a, b] of CONNECTIONS) {
    if (!landmarks[a] || !landmarks[b]) continue;
    ctx.beginPath();
    ctx.moveTo(...px(landmarks[a]));
    ctx.lineTo(...px(landmarks[b]));
    ctx.stroke();
  }

  ctx.fillStyle = color;
  for (const lm of landmarks) {
    if (!lm) continue;
    const [x, y] = px(lm);
    ctx.beginPath();
    ctx.arc(x, y, 4, 0, Math.PI * 2);
    ctx.fill();
  }
}
