// 눕기(tilt가 낮음→수평으로 상승) 구간을 찾아 하강 중 hipV 피크와 소요시간을 재는 스크립트
// 눕기가 느렸는데도 hipV가 0.45를 넘으면 배치 문제, 빠를 때만 넘으면 속도 문제다.

import { readFileSync } from "node:fs";

const csvPath = process.argv[2];
const rows = readFileSync(csvPath, "utf8")
  .trim()
  .split("\n")
  .slice(1)
  .map((line) => {
    const [take, t, state, tilt, hipV] = line.split(",");
    return { t: Number(t), state, tilt: Number(tilt), hipV: Number(hipV) };
  });

const LOW = 15; // 이 아래면 서 있음
const HIGH = 65; // 이 위면 누움

// tilt가 LOW 미만에서 HIGH 초과로 올라가는 구간 = 눕기. 각 구간의 하강 hipV 피크와 시간을 잰다.
const events = [];
let i = 0;
while (i < rows.length) {
  if (rows[i].tilt < LOW) {
    // 여기서부터 tilt가 HIGH를 넘는 지점을 찾는다. 도중에 다시 LOW로 떨어지면 리셋.
    let j = i + 1;
    let startIdx = i;
    let reached = -1;
    while (j < rows.length) {
      if (rows[j].tilt < LOW) startIdx = j; // 눕기 시작점 갱신
      if (rows[j].tilt > HIGH) {
        reached = j;
        break;
      }
      j += 1;
    }
    if (reached === -1) break;
    let peak = -Infinity;
    for (let k = startIdx; k <= reached; k += 1) peak = Math.max(peak, rows[k].hipV);
    events.push({
      from: rows[startIdx].t,
      to: rows[reached].t,
      dur: (rows[reached].t - rows[startIdx].t) / 1000,
      peak,
    });
    // 이 눕기 이후 다시 서는 지점까지 건너뛴다.
    let m = reached;
    while (m < rows.length && rows[m].tilt >= LOW) m += 1;
    i = m;
  } else {
    i += 1;
  }
}

console.log("\n눕기 구간 (tilt <15° → >65°)\n");
console.log("시작(s)  소요(s)  하강 중 hipV 피크   관문1(0.45)");
for (const e of events) {
  console.log(
    `${(e.from / 1000).toFixed(1).padStart(6)}  ${e.dur.toFixed(1).padStart(6)}  ${e.peak.toFixed(3).padStart(14)}   ${e.peak > 0.45 ? "❌ 넘음" : "✅ 안 넘음"}`,
  );
}
console.log(`\n총 ${events.length}회 눕기.`);
console.log();
