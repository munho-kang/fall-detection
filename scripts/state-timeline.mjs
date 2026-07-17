// 튜닝 CSV의 state 열에서 상태 전이 타임라인을 뽑아 낙상 감지와 5초 알림을 확인하는 스크립트
// 사용법: node state-timeline.mjs <csv>

import { readFileSync } from "node:fs";

const csvPath = process.argv[2];
if (!csvPath) {
  console.error("사용법: node state-timeline.mjs <csv>");
  process.exit(1);
}

const rows = readFileSync(csvPath, "utf8")
  .trim()
  .split("\n")
  .slice(1)
  .map((line) => {
    const [take, t, state, tilt, hipV] = line.split(",");
    return { take: Number(take), t: Number(t), state, tilt: Number(tilt), hipV: Number(hipV) };
  });

// tilt가 60°를 넘기 직전 1초 구간의 hipV 최대치 — 관문 1이 낙상에서 실제로 열렸는지 본다.
function gateWindowPeak(idx) {
  const t0 = rows[idx].t;
  let peak = -Infinity;
  for (let i = idx; i >= 0 && rows[i].t > t0 - 1000; i -= 1) {
    peak = Math.max(peak, rows[i].hipV);
  }
  return peak;
}

console.log("\n상태 전이 타임라인\n");
console.log("시각(s)   이전 → 다음            머문시간   tilt    hipV");

let prev = rows[0].state;
let prevAt = rows[0].t;
const fallingOnsets = [];
let alertedCount = 0;

for (let i = 1; i < rows.length; i += 1) {
  const r = rows[i];
  if (r.state === prev) continue;

  const dwell = ((r.t - prevAt) / 1000).toFixed(1);
  console.log(
    `${(r.t / 1000).toFixed(1).padStart(7)}   ${prev.padEnd(10)} → ${r.state.padEnd(10)} ${`${dwell}s`.padStart(8)}   ${r.tilt.toFixed(0).padStart(3)}°   ${r.hipV.toFixed(3).padStart(6)}`,
  );

  if (r.state === "FALLING") fallingOnsets.push(i);
  if (r.state === "ALERTED") alertedCount += 1;

  prev = r.state;
  prevAt = r.t;
}

console.log("\n\n낙상별 관문 통과 요약\n");
console.log(`FALLING 진입 횟수: ${fallingOnsets.length}`);
console.log(`ALERTED 도달 횟수: ${alertedCount}`);
console.log("");
for (const idx of fallingOnsets) {
  const r = rows[idx];
  const peak = gateWindowPeak(idx);
  console.log(`${(r.t / 1000).toFixed(1).padStart(7)}s  FALLING 진입 hipV ${r.hipV.toFixed(3)}  |  직전 1초 hipV 피크 ${peak.toFixed(3)}`);
}
console.log();
