# 노인 낙상 감지 시스템

혼자 사는 노인의 낙상을 카메라로 감지해 보호자 앱에 알린다. **영상은 기기를 벗어나지 않는다.**

과제 제출용 프로젝트이며 실제 배포하지 않는다.

## 사생활 보호

이 프로젝트의 출발점은 "감시 카메라를 집 안에 두는 거부감"이다. 그래서 영상을 서버로 보내지 않는 것을 구조로 보장했다.

- MediaPipe Pose를 **브라우저에서** 실행한다. 웹캠 영상은 브라우저 안에서 관절 좌표가 된다.
- **관절 좌표조차 서버로 보내지 않는다.** 낙상이 확정된 순간에만 `{room_name, room_number, occurred_at, confidence}` 4개 필드가 1회 전송된다.
- 화면에도 원본 영상을 표시하지 않는다. 검은 배경 위 스켈레톤만 그린다. 디버그용 영상 토글도 없다.

## 구조

```
[웹캠] → 브라우저 (web/)
           │  MediaPipe로 랜드마크 추출 → 상태머신 판정
           │  ※ 영상·랜드마크 전부 브라우저 밖으로 안 나감
           │
           └─ 낙상 확정 시에만 1회
              POST /api/falls/  (Token 헤더)
                      │
                 [Django + SQLite]  (backend/)
                      │
              GET /api/falls/  ← 5초마다 폴링
                      │
                 [Flutter] → 새 id 발견 시 로컬 알림  (app/)
```

## 감지 알고리즘 — 세 관문

낙상 감지의 진짜 난제는 **"넘어짐"과 "그냥 누움"의 구분**이다. "몸통이 수평이면 낙상"이라는 단순 임계값은 침대에 눕는 것도 전부 잡는다.

```
STANDING ──속도──▶ FALLING ──자세──▶ FALLEN ──시간──▶ ALERTED ──▶ POST 1회
```

1. **속도** (`hipVelocity > 0.45/s`) — 천천히 눕거나 앉으면 하강 속도가 임계값에 못 미쳐 진입조차 안 한다. 오탐지 방어의 1차 관문이다.
2. **자세** (`tilt > 60°`) — 빠르게 내려갔어도 몸통이 서 있으면 급히 앉은 것이다. 1초 안에 수평이 돼야 넘어진 것으로 본다.
3. **시간** (`5초 미회복`) — 5초 안에 일어나면 아무것도 보내지 않는다. 스스로 일어난 사람 때문에 보호자를 깨우지 않는다.

`TILT_UPRIGHT`(45°)와 `TILT_FALLEN`(60°) 사이 15°는 **의도적인 히스테리시스 밴드**다. 하나로 합치면 경계에서 상태가 진동한다.

`occurred_at`은 확정 시각이 아니라 **FALLING 진입 시각**이다. 보호자에게 실제로 넘어진 순간이 표시되어야 한다.

## 실행 방법

터미널 3개가 필요하다.

### 1. Django (`:8000`)

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python manage.py migrate
.venv/bin/python manage.py createsuperuser   # 보호자 계정 (회원가입 화면은 범위 밖)
.venv/bin/python manage.py runserver 8000
```

### 2. 감지 페이지 (`:5500`)

```bash
cd web
npx serve -l 5500 .
```

`http://127.0.0.1:5500`에서 로그인 → 방 선택 → 감지 시작 → 카메라 권한 허용.

포트가 **5500이어야 한다.** Django의 `CORS_ALLOWED_ORIGINS`가 이 포트만 허용한다. `getUserMedia`는 보안 컨텍스트를 요구하지만 `localhost`는 예외라 HTTPS는 불필요하다.

### 3. Flutter 앱

```bash
cd app
flutter pub get
flutter run
```

서버 주소는 플랫폼에 따라 자동으로 갈린다 — Android 에뮬레이터는 `10.0.2.2:8000`, iOS 시뮬레이터는 `127.0.0.1:8000`.

## 테스트

```bash
cd backend && .venv/bin/python -m pytest    # 7개 — 인증·소유권·멱등성
cd web     && npm test                       # 7개 — 상태머신 시나리오
cd app     && flutter test                   # 4개 — 새 이벤트 판별
```

상태머신 테스트가 이 프로젝트 테스트의 핵심이다. 가짜 랜드마크 시퀀스로 "천천히 눕기 → 알림 없음", "3초 만에 일어남 → 알림 없음", "5초 유지 → 1건" 같은 시나리오를 웹캠 없이 검증한다.

## 알려진 한계

의도적으로 범위 밖에 둔 것들이다.

- **임계값 실측 검증 없음** — `CONFIG`의 7개 값(FALL_VELOCITY 0.45/s, TILT_UPRIGHT 45°, TILT_FALLEN 60°, FALLING_WINDOW 1000ms, FALLEN_HOLD 5000ms, EMA_ALPHA 0.4, NO_PERSON_TIMEOUT 2000ms)은 전부 설계 단계의 추정치이고 실제 사람 앞에서, 실제 방에서 웹캠으로 재본 적이 없다. 그래서 오탐지·미탐지가 실제 상황에서 어떻게 나타날지는 검증되지 않았다 — Vitest 7개 시나리오는 랜드마크가 주어졌을 때 상태머신 로직이 맞다는 것만 증명하며, `0.45/s`가 눕기와 넘어짐을 가르는 실제 경계값인지는 아무것도 말해주지 않는다. 이를 확인하려면 계획의 Task 16 Step 1~3(웹캠 앞에서 서기·천천히 눕기·빨리 앉기·넘어지기를 재현해 값을 재고 튜닝하는 작업)이 필요한데 아직 수행하지 않았다. 재야 할 구체적인 항목은 `context-notes.md`의 "임계값 튜닝 기록" 절에 있다.
- **백그라운드 알림 불가** — 폴링 방식이라 앱이 백그라운드로 가면 멈춘다. 실제 제품이라면 FCM이 필요하다. Firebase 설정에서 깨질 지점이 많아 시연 안정성을 택했다.
- **프레임 밖 낙상** — 넘어지며 화면을 벗어나면 `NO_PERSON`이 되어 감지되지 않는다.
- **다중 인물** — `numPoses: 1`, 독거 전제다.
- **낙상 전송 유실** — POST 3회 재시도 후 포기하고 배너만 띄운다. 실제 제품이라면 localStorage 큐가 필요하다.
- **회원가입·방 등록·연락처 관리 화면 없음** — 계정은 `createsuperuser`, 방은 고정 선택지 4개, 연락처는 상수다.
- **119는 더미 번호** — 시연 중 실제 발신을 막기 위함이다. `fall_detail.dart`의 `_emergencyPhone` 참고.
- **실시간 방 상태 대시보드 없음** — 웹캠이 하나라 의미가 없다.

## 문서

- [설계](docs/superpowers/specs/2026-07-17-fall-detection-design.md)
- [구현 계획](docs/superpowers/plans/2026-07-17-fall-detection.md)
- [결정 기록](context-notes.md)
