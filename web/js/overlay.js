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

// css/style.css의 상태 색과 같은 값이다 — 뼈대 색과 화면 색이 어긋나면 안 된다
const STATE_COLOR = {
  NO_PERSON: "#8593af",
  STANDING: "#2bd9a0",
  FALLING: "#ffb020",
  FALLEN: "#ffb020",
  ALERTED: "#ff5c63",
};

export function drawSkeleton(ctx, landmarks, state) {
  const { width, height } = ctx.canvas;

  // 낙상 확정 구간에만 바탕에 아주 옅은 붉은 기운이 돈다 (영상은 여전히 그리지 않는다)
  ctx.fillStyle = state === "ALERTED" ? "#1a0709" : "#000";
  ctx.fillRect(0, 0, width, height);

  if (!landmarks || landmarks.length === 0) return;

  const color = STATE_COLOR[state] ?? "#8593af";
  const px = (lm) => [lm.x * width, lm.y * height];

  // 뼈대가 멀리서도 읽히도록 굵게, 은은한 발광을 준다 — 프로젝터에서 검은 바탕에 묻히지 않는다
  ctx.shadowColor = color;
  ctx.shadowBlur = 14;
  ctx.strokeStyle = color;
  ctx.lineWidth = 5;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  for (const [a, b] of CONNECTIONS) {
    if (!landmarks[a] || !landmarks[b]) continue;
    ctx.beginPath();
    ctx.moveTo(...px(landmarks[a]));
    ctx.lineTo(...px(landmarks[b]));
    ctx.stroke();
  }

  ctx.shadowBlur = 0;
  ctx.fillStyle = color;
  for (const lm of landmarks) {
    if (!lm) continue;
    const [x, y] = px(lm);
    ctx.beginPath();
    ctx.arc(x, y, 4.5, 0, Math.PI * 2);
    ctx.fill();
  }
}
