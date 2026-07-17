// 튜닝 CSV를 읽어 시행별 피크를 뽑고 FALL_VELOCITY 기준을 대보는 분석기
// 사용법: node scripts/analyze-tuning.mjs <csv> "1=stand 2-6=lie 7-11=sit 12-16=fall 17=prone-side 18=prone-front 19=prone-diag"
// 튜닝이 끝나면 web/js/tuning.js와 함께 제거해도 된다.

import { readFileSync } from "node:fs";

const TILT_FALLEN = 60; // detector.js CONFIG와 맞춰 읽는다

const [csvPath, spec] = process.argv.slice(2);
if (!csvPath || !spec) {
  console.error('사용법: node scripts/analyze-tuning.mjs <csv> "1=stand 2-6=lie ..."');
  process.exit(1);
}

// "2-6=lie" 또는 "1=stand" 형태를 take 번호 → 동작 이름 맵으로 편다.
function parseSpec(text) {
  const map = new Map();
  for (const part of text.trim().split(/\s+/)) {
    const [range, action] = part.split("=");
    if (!action) throw new Error(`형식이 잘못됐다: ${part}`);
    const [lo, hi] = range.split("-").map(Number);
    if (!Number.isInteger(lo)) throw new Error(`시행 번호가 아니다: ${part}`);
    for (let t = lo; t <= (Number.isInteger(hi) ? hi : lo); t += 1) map.set(t, action);
  }
  return map;
}

const actionOf = parseSpec(spec);
const takes = new Map();

for (const line of readFileSync(csvPath, "utf8").trim().split("\n").slice(1)) {
  const [take, t, , tilt, hipV] = line.split(",");
  const n = Number(take);
  if (!takes.has(n)) {
    takes.set(n, { n, frames: 0, tMin: Infinity, tMax: -Infinity, tiltMin: Infinity, tiltMax: -Infinity, hipVMax: -Infinity });
  }
  const k = takes.get(n);
  k.frames += 1;
  k.tMin = Math.min(k.tMin, Number(t));
  k.tMax = Math.max(k.tMax, Number(t));
  k.tiltMin = Math.min(k.tiltMin, Number(tilt));
  k.tiltMax = Math.max(k.tiltMax, Number(tilt));
  k.hipVMax = Math.max(k.hipVMax, Number(hipV));
}

const rows = [...takes.values()].sort((a, b) => a.n - b.n);

console.log("\n시행별 피크\n");
console.log("시행  동작           프레임  길이(s)  tilt 범위        hipV 피크");
for (const r of rows) {
  const action = actionOf.get(r.n) ?? "(라벨없음)";
  const dur = ((r.tMax - r.tMin) / 1000).toFixed(1);
  const tilt = `${r.tiltMin.toFixed(0)}~${r.tiltMax.toFixed(0)}°`;
  console.log(
    `${String(r.n).padEnd(5)} ${action.padEnd(14)} ${String(r.frames).padStart(6)} ${dur.padStart(7)}  ${tilt.padEnd(15)} ${r.hipVMax.toFixed(3)}`,
  );
  // r을 잘못 눌러 시행이 쪼개지면 피크가 반토막 난다. 눈에 띄게 경고한다.
  if (r.frames < 15) console.log(`      ⚠ 프레임이 ${r.frames}개뿐이다. r을 잘못 눌러 시행이 쪼개졌을 수 있다`);
}

const peaksOf = (...actions) =>
  rows.filter((r) => actions.includes(actionOf.get(r.n))).map((r) => r.hipVMax);

const negative = peaksOf("lie", "sit"); // 알림이 뜨면 안 되는 동작
const positive = peaksOf("fall"); // 반드시 잡아야 하는 동작

console.log("\n\nFALL_VELOCITY 판정\n");
if (!negative.length || !positive.length) {
  console.log("lie/sit 또는 fall 라벨이 없어 판정할 수 없다.");
} else {
  const ceil = Math.max(...negative);
  const floor = Math.min(...positive);
  console.log(`오탐지 쪽 최대 (눕기·앉기 ${negative.length}회): ${ceil.toFixed(3)}`);
  console.log(`미탐지 쪽 최소 (넘어지기 ${positive.length}회): ${floor.toFixed(3)}`);

  if (ceil < floor) {
    // 구간 한가운데를 잡아야 양쪽 여유가 같아진다.
    console.log(`\n✅ 구간이 분리됐다. 여유 ${(floor - ceil).toFixed(3)}`);
    console.log(`   FALL_VELOCITY 제안값: ${((ceil + floor) / 2).toFixed(2)}  (${ceil.toFixed(3)} ~ ${floor.toFixed(3)} 사이 아무 값)`);
  } else {
    console.log(`\n❌ 구간이 ${(ceil - floor).toFixed(3)}만큼 겹친다. 속도만으로는 눕기와 넘어지기가 안 갈린다.`);
    console.log("   임계값을 억지로 고르지 말고 카메라를 방 모서리 높은 곳으로 옮겨 몸 전체가 프레임에 들어오게 한 뒤 다시 잰다.");
  }
}

console.log("\n\ntilt 사각지대 판정\n");
const prone = rows.filter((r) => (actionOf.get(r.n) ?? "").startsWith("prone"));
if (!prone.length) {
  console.log("prone-* 라벨이 없어 판정할 수 없다.");
} else {
  for (const r of prone) {
    const ok = r.tiltMax > TILT_FALLEN;
    console.log(`${actionOf.get(r.n).padEnd(14)} tilt 최대 ${r.tiltMax.toFixed(1)}°  ${ok ? "✅ TILT_FALLEN(60°) 넘음" : "❌ 60°를 못 넘어 FALLEN 진입 불가"}`);
  }
  if (prone.some((r) => r.tiltMax <= TILT_FALLEN)) {
    console.log("\n못 넘긴 방향이 있다면 TILT_FALLEN을 낮추지 마라. 낮추면 앉기 오탐지가 터진다.");
    console.log("카메라를 옆에서 보는 각도로 옮기거나 README의 알려진 한계에 추가한다.");
  }
}
console.log();
