// 감지 상태를 화면에 그린다 — 판정 문구, 세 관문 미터, 응급 대응 타임라인.
// 판정에는 관여하지 않는다. 값을 받아 DOM만 바꾼다.

import { CONFIG as DETECT } from "./detector.js";
import { CONFIG as ESC } from "./escalation.js";

// 상태머신의 영어 상태를 화면 문구와 색 단계로 옮긴다
const VERDICT = {
  NO_PERSON: ["idle", "사람이 보이지 않아요", "카메라 앞에 아무도 없습니다"],
  STANDING: ["safe", "지금은 안전해요", "서 있거나 앉아 있습니다"],
  FALLING: ["watch", "넘어지는 중", "빠르게 내려갔습니다 — 자세를 확인합니다"],
  FALLEN: ["watch", "쓰러짐 — 지켜보는 중", "5초 안에 일어나면 알리지 않습니다"],
  ALERTED: ["crit", "낙상 확정", "보호자에게 알림을 보냈습니다"],
};

// 관문은 순서대로 열린다 — 상태 하나가 "몇 번째까지 통과했나"를 그대로 알려 준다
const PASSED = { NO_PERSON: 0, STANDING: 0, FALLING: 1, FALLEN: 2, ALERTED: 3 };

const MARK = 0.7; // 기준선을 막대의 70% 지점에 둔다 — 기준을 넘어선 만큼도 보이게 남긴 여백이다

// 응급 대응 단계. 시각은 전부 쓰러진 순간(FALLEN 진입) 기준이다.
const STEPS = [DETECT.FALLEN_HOLD, ESC.QUESTION_AT, ESC.REPORT_AT];

// 열린 관문은 막대가 기준선 밑으로 내려가지 않는다 — 넘어진 뒤 속도가 0으로 돌아가도
// "이 관문은 열렸다"가 계속 보여야 한다. 옆의 숫자는 현재값 그대로다.
const bar = (value, threshold, passed) =>
  `${Math.max(Math.min((value / threshold) * MARK, 1), passed ? MARK : 0) * 100}%`;

export function createView(el) {
  // 관문 3개는 구조가 같다 — 한 번만 찾아 두고 값만 갈아 끼운다
  const gates = [el.gate1, el.gate2, el.gate3].map((root) => ({
    root,
    value: root.querySelector(".gate-value"),
    fill: root.querySelector(".gate-fill"),
    state: root.querySelector(".gate-state em"),
  }));

  function gate(i, passed, text, value, threshold) {
    const g = gates[i];
    g.value.textContent = text;
    g.fill.style.width = bar(value, threshold, passed);
    g.state.textContent = passed ? "통과" : "대기";
    g.root.toggleAttribute("data-passed", passed);
  }

  return {
    // 매 프레임 — 판정 문구와 세 관문
    frame({ state, tilt, hipVelocity, fallenFor }) {
      const [level, head, sub] = VERDICT[state] ?? VERDICT.NO_PERSON;
      document.body.dataset.level = level;
      el.verdict.textContent = head;
      el.verdictSub.textContent = sub;

      const passed = PASSED[state] ?? 0;
      gate(0, passed >= 1, hipVelocity.toFixed(2), hipVelocity, DETECT.FALL_VELOCITY);
      gate(1, passed >= 2, `${(tilt ?? 0).toFixed(0)}°`, tilt ?? 0, DETECT.TILT_FALLEN);
      gate(2, passed >= 3, `${(fallenFor / 1000).toFixed(1)}초`, fallenFor, DETECT.FALLEN_HOLD);
    },

    // 응급 구간에만 보이는 타임라인. statusText가 없으면 구간이 아니다.
    escalation({ state, statusText, elapsed }) {
      el.escalation.classList.toggle("hidden", !statusText);
      if (!statusText) return;

      const resolved = state === "RESOLVED";
      const reported = state === "REPORTED";
      const done = (i) => (i === 2 ? reported : elapsed >= STEPS[i]);

      el.escalation.toggleAttribute("data-resolved", resolved);
      el.escalation.toggleAttribute("data-reported", reported);
      el.escalationStatus.textContent = statusText;

      // 아직 지나지 않은 첫 단계가 지금 기다리는 단계다
      const next = STEPS.findIndex((_, i) => !done(i));
      for (const [i, step] of [el.step1, el.step2, el.step3].entries()) {
        step.toggleAttribute("data-done", done(i));
        step.toggleAttribute("data-now", !resolved && i === next);
      }

      // 남은 시간은 다음 단계까지만 센다 — 종결(응답·신고) 뒤에는 셀 것이 없다
      const remain = next < 0 || resolved ? 0 : Math.ceil((STEPS[next] - elapsed) / 1000);
      el.countdown.innerHTML = remain > 0 ? `${remain}<small>초 남음</small>` : "";
    },
  };
}
