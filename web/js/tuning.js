// 임계값 실측 튜닝용 측정 패널 — 시행별 피크 표시와 시계열 CSV 내보내기
// 판정에는 관여하지 않는다. 튜닝이 끝나면 이 파일과 호출부를 통째로 제거해도 된다.

const EMPTY = { hipVMax: -Infinity, tiltMin: Infinity, tiltMax: -Infinity };

export function createTuningRecorder({ peakEl, downloadEl }) {
  const rows = [];
  let take = 1;
  let peak = { ...EMPTY };

  function render() {
    if (peak.hipVMax === -Infinity) {
      peakEl.textContent = `시행 ${take} — 측정 대기`;
      return;
    }
    peakEl.textContent =
      `시행 ${take}  ·  hipV max ${peak.hipVMax.toFixed(2)}/s  ·  ` +
      `tilt ${peak.tiltMin.toFixed(1)}° ~ ${peak.tiltMax.toFixed(1)}°`;
  }

  // 한 동작을 마칠 때마다 r을 눌러 시행을 끊는다. take 번호가 CSV에 같이 실리므로
  // 나중에 어느 행이 어느 시행인지 되짚을 수 있다.
  window.addEventListener("keydown", (e) => {
    if (e.key !== "r" && e.key !== "R") return;
    take += 1;
    peak = { ...EMPTY };
    render();
  });

  downloadEl.addEventListener("click", () => {
    const csv = ["take,t_ms,state,tilt_deg,hipV_per_s"]
      .concat(
        rows.map(
          (r) =>
            `${r.take},${r.t.toFixed(1)},${r.state},${r.tilt.toFixed(2)},${r.hipV.toFixed(3)}`,
        ),
      )
      .join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `tuning-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  });

  render();

  return {
    record(t, state, tilt, hipV) {
      if (tilt === null) return; // 미검출 프레임은 잴 값이 없다
      rows.push({ take, t, state, tilt, hipV });
      if (hipV > peak.hipVMax) peak.hipVMax = hipV;
      if (tilt < peak.tiltMin) peak.tiltMin = tilt;
      if (tilt > peak.tiltMax) peak.tiltMax = tilt;
      render();
    },
  };
}
