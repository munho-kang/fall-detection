# 수동 검증 체크리스트

자동화할 수 없어 사람이 직접 해야 하는 검증만 모았다. 웹캠·카메라 권한·iOS 시뮬레이터·실제 알림이 필요한 항목들이다.
코드와 자동 테스트(backend 7 / web 10 / app 4)는 전부 통과한 상태다.

## 준비

터미널 3개가 필요하다. 계정은 `guardian` / `pw12345` (로컬 `db.sqlite3`에 이미 있다).

```bash
cd backend && .venv/bin/python manage.py runserver 8000   # 터미널 1
cd web && npx --yes serve -l 5500 .                        # 터미널 2
cd app && flutter run                                      # 터미널 3
```

포트는 **5500이어야 한다.** Django의 `CORS_ALLOWED_ORIGINS`가 이 포트만 허용한다.

---

## 1. 로그인 (Task 7)

- [ ] `http://127.0.0.1:5500`에서 `guardian` / `pw12345`로 로그인 → `detect.html`로 이동
- [ ] DevTools 콘솔에 CORS 에러가 없다
- [ ] Application → Local Storage에 `fall_token`이 있다
- [ ] 틀린 비밀번호 → 빨간 에러 문구가 뜨고 버튼이 다시 활성화된다

## 2. 감지 화면 (Task 10)

- [ ] **캔버스에 검은 배경과 스켈레톤만 보인다. 원본 영상이 보이면 버그다.** `startCamera` 직후 첫 몇 프레임에 영상이 번쩍이지 않는지 특히 본다
- [ ] 카메라 앞에 서면 `STANDING`(파랑), 프레임을 벗어나 2초 지나면 `NO_PERSON`(회색)
- [ ] `tilt`가 서 있을 때 0~15°, 누우면 70~90°
- [ ] 천천히 눕는다 → `FALLING`으로 가지 않는다
- [ ] 빠르게 눕고 5초 버틴다 → `FALLING` → `FALLEN` → `ALERTED`(빨강)
- [ ] 카메라 권한을 "차단"으로 바꾸고 새로고침 → 감지 시작 → 한국어 에러 문구가 뜨고 버튼이 다시 활성화된다

> **주의**: `createPoseLandmarker()`가 `startCamera()`보다 먼저 await된다. 모델 다운로드가 느리면 클릭의 user-activation이 만료되어 `video.play()`가 `NotAllowedError`를 던지고, 권한을 허용했는데도 "웹캠을 사용할 수 없습니다"가 뜰 수 있다. 이게 보이면 `pose.js`를 고쳐야 한다.

## 3. 낙상 전송 (Task 11)

- [ ] 넘어져서 확정시키고 DB 확인 — `occurred_at`이 **오늘 날짜의 현재 시각 근처**여야 한다. 1970년이면 `performance.timeOrigin` 변환이 깨진 것이다

```bash
cd backend && .venv/bin/python manage.py shell -c "
from falls.models import FallEvent
for e in FallEvent.objects.all()[:5]: print(e.id, e.room_name, e.room_number, e.occurred_at, round(e.confidence,3))
"
```

- [ ] **DevTools Network 탭에 영상·랜드마크 요청이 없고 `POST /api/falls/`만 있다** — 이 프로젝트의 핵심 주장이다
- [ ] Django를 끄고 넘어진다 → **약 1.5초** 뒤 빨간 배너. Network 탭에 `/api/falls/` 요청이 정확히 3번
  - 계획서는 3.5초라고 했지만 틀렸다. 재시도 사이에만 sleep하므로 3회 시도 = sleep 2번(0.5+1초) = 1.5초다
- [ ] 콘솔에서 `localStorage.setItem("fall_token","broken")` 후 넘어진다 → 재시도 없이(요청 1번) 즉시 `index.html`로 튕기고 `fall_token`이 사라진다

## 4. 앱 화면 (Task 13)

- [ ] 로그인 후 DB의 이벤트가 목록에 뜬다
- [ ] 항목 → 상세 → "확인함으로 표시" → 버튼이 비활성화되고 상태가 "확인함"으로 바뀐다
- [ ] **AppBar 백버튼**으로 나가면 목록 아이콘이 **즉시** 초록 체크로 바뀐다
- [ ] iOS 스와이프 백으로 나가면 아이콘이 바로 안 바뀔 수 있다 — **정상이다.** 5초 폴링이 곧 갱신한다

## 5. 알림 (Task 15)

- [ ] **로그인 직후에는 기존 이벤트가 있어도 알림이 뜨지 않는다.** 뜨면 최초 id 저장 로직이 깨진 것이다
- [ ] 브라우저에서 넘어진다 → 5초 안에 "안방 1에서 낙상 감지" 알림. 목록 맨 위에 새 항목
- [ ] 상세에서 "어르신께 전화" → 다이얼러에 `01012345678`이 뜨고 **자동 발신되지 않는다**
  - **iOS 시뮬레이터에는 전화 앱이 없어서** `tel:`이 안 열리고 "전화 앱을 열 수 없습니다." SnackBar가 뜬다. 시뮬레이터 한계이지 버그가 아니다. 실기기에서 확인해야 진짜 검증이다
- [ ] Django를 끈다 → 약 15초(5초 × 3회) 뒤 "연결 끊김 — 서버에 닿지 않습니다." 배너. 다시 띄우면 5초 안에 사라진다

## 6. 임계값 실측 튜닝 (Task 16 Step 1~3) — 가장 중요

**현재 `CONFIG`의 7개 값은 전부 설계 단계의 추정치이고 실제 사람 앞에서 재본 적이 없다.** Vitest 10개는 랜드마크가 주어졌을 때 상태머신 로직이 맞다는 것만 증명한다. `0.45/s`가 "눕기"와 "넘어지기"의 실제 경계인지는 아무것도 말해주지 않는다.

감지 화면의 `tilt` / `hipV` 표시를 보며 잰다.

| 동작 | 관찰할 값 |
|---|---|
| 가만히 서 있기 | `tilt` 범위, `hipV` 노이즈 폭 |
| 침대에 천천히 눕기 | `hipV` 최대치 → `FALL_VELOCITY`가 이보다 **커야** 한다 |
| 의자에 급히 앉기 | `hipV` 최대치, `tilt` 최대치 |
| 빠르게 넘어지기 | `hipV` 최대치 → `FALL_VELOCITY`가 이보다 **작아야** 한다 |
| 바닥에 누워 있기 | `tilt` 범위 |

- [ ] 위 5개 실측
- [ ] `FALL_VELOCITY`가 "천천히 눕기 최대치"와 "빠르게 넘어지기 최대치" **사이**에 들어가는지 확인. 두 구간이 겹치면 카메라 각도 문제다 — 방 모서리 높은 곳에 두고 몸 전체가 프레임에 들어오게 다시 잡는다
- [ ] 조정했다면 `web/js/detector.js`의 `CONFIG` 값만 바꾸고 `npx vitest run` 재실행 (10개 통과 유지). 상태머신 구조는 건드리지 않는다
- [ ] 조정 내역과 이유를 `context-notes.md`의 "임계값 튜닝 기록" 표에 기록
- [ ] **3회 연속** 통과: ① 빠르게 넘어져 5초 → 알림 ② 천천히 눕기 → 알림 없음 ③ 급히 앉기 → 알림 없음
