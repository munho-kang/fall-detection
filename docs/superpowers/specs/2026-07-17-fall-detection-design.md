# 노인 낙상 감지 시스템 — 설계

작성일: 2026-07-17
상태: 승인됨

## 1. 문제와 목적

혼자 사는 노인이 낙상 사고를 당했을 때, 본인이 신고를 하지 못하고 보호자도 상황을 즉시 알지 못한다. 이 시스템은 각 방의 카메라가 낙상을 자동으로 감지해 보호자의 앱으로 알림을 보내고, 보호자가 곧바로 연락하거나 신고할 수 있게 한다.

핵심 제약은 **사생활 보호**다. 감시 카메라를 집 안에 두는 것에 대한 거부감이 이런 시스템의 가장 큰 도입 장벽이므로, 영상이 기기 밖으로 나가지 않는다는 것이 설계의 출발점이다.

이 프로젝트는 과제 제출용이며 실제 배포하지 않는다.

## 2. 사생활 보호 방식

MediaPipe Pose를 **브라우저에서** 실행한다. 웹캠 영상은 브라우저 안에서 관절 좌표로 변환되고, 그 좌표조차 서버로 보내지 않는다. 낙상이 확정된 순간에만 아래 텍스트 데이터가 전송된다.

```
{ room_name, room_number, occurred_at, confidence }
```

화면에도 원본 영상을 표시하지 않는다. 검은 배경 위에 스켈레톤만 그린다. 사생활 보호가 눈으로 확인되도록 하기 위함이다.

## 3. 아키텍처

```
weniv_project/
├── web/          감지 클라이언트 (정적, Live Server :5500)
├── backend/      Django + DRF (:8000)
└── app/          Flutter 보호자 앱
```

### 데이터 흐름

```
[웹캠] → web/ 브라우저
           │  MediaPipe로 랜드마크 추출 → 상태머신 판정
           │  ※ 영상·이미지·랜드마크 전부 브라우저 밖으로 안 나감
           │
           └─ 낙상 확정 시에만 1회
              POST /api/falls/  (Token 헤더)
                      │
                 [Django + SQLite]
                      │
              GET /api/falls/  ← 5초마다 폴링
                      │
                 [Flutter] → 새 id 발견 시 로컬 알림
```

### 결정 사항과 근거

| 결정 | 선택 | 근거 |
|---|---|---|
| 감지 위치 | 브라우저 | 영상이 네트워크를 타지 않아야 사생활 보호가 구조적으로 보장됨 |
| 알림 전달 | 폴링 + 로컬 알림 | 외부 의존성 0, 에뮬레이터에서 바로 시연 가능. FCM은 Firebase 설정에서 깨질 지점이 많음 |
| 감지 알고리즘 | 3단계 상태머신 | 넘어짐과 눕기의 구분이 핵심 난제. 오탐지 방어 논리가 설명 자료가 됨 |
| 방 구성 | 페이지에서 선택 후 시작 | 브라우저 탭 1개 = 카메라 1대 = 방 1개로 대응. 웹캠이 하나라는 현실과 맞음 |
| 인증 | DRF 토큰 | 감지 페이지와 앱이 같은 보호자 계정으로 로그인 |
| 서빙 | 정적 사이트 분리 + CORS | 프론트/백 경계가 선명함 |

## 4. 데이터 모델

방 등록 화면이 없으므로 `Room` 테이블을 두지 않고 방 정보를 이벤트에 직접 저장한다. 새 모델은 하나뿐이다.

```python
class FallEvent(models.Model):
    ROOM_CHOICES = [("안방", "안방"), ("부엌", "부엌"),
                    ("거실", "거실"), ("화장실", "화장실")]

    guardian        = FK(User, related_name="fall_events")
    room_name       = CharField(choices=ROOM_CHOICES)
    room_number     = PositiveSmallIntegerField()
    occurred_at     = DateTimeField()        # 클라이언트가 판정한 낙상 시각
    created_at      = DateTimeField(auto_now_add=True)
    confidence      = FloatField()           # 판정 시점 랜드마크 평균 visibility
    acknowledged_at = DateTimeField(null=True, blank=True)
```

보호자는 Django 기본 `User`를 그대로 쓴다.

## 5. API

| 메서드 | 경로 | 용도 |
|---|---|---|
| POST | `/api/auth/login/` | `{username, password}` → `{token}` |
| POST | `/api/falls/` | 낙상 등록 (감지 페이지) |
| GET | `/api/falls/` | 목록, 최신순 (앱 화면 + 폴링 겸용) |
| POST | `/api/falls/<id>/acknowledge/` | 확인 처리 |

- 모든 `/api/falls/` 응답은 `request.user`의 이벤트로만 필터링한다.
- POST 시 `guardian`은 요청자로 강제한다. 클라이언트가 보낸 값은 무시한다.
- 목록 조회와 폴링을 한 엔드포인트로 겸한다. 앱이 마지막으로 본 id를 로컬에 들고 있다가 응답의 최대 id와 비교하므로 `since` 파라미터가 필요 없다.

### 접속 주소 주의사항

- 감지 페이지 `:5500`, Django `:8000` → `django-cors-headers`로 `http://127.0.0.1:5500`, `http://localhost:5500` 허용
- `getUserMedia`는 보안 컨텍스트를 요구하지만 `localhost`는 예외이므로 HTTPS 불필요
- Android 에뮬레이터에서 호스트의 Django는 `10.0.2.2:8000` (`127.0.0.1` 아님)

## 6. 감지 알고리즘

### MediaPipe 설정

`@mediapipe/tasks-vision`의 `PoseLandmarker`를 CDN에서 ESM으로 import한다. 번들러 없이 `<script type="module">`로 동작한다.

- 모델: `pose_landmarker_lite.task`
- `runningMode: "VIDEO"`, `numPoses: 1` (독거노인 전제)

33개 랜드마크 중 4개만 사용한다.

| 인덱스 | 부위 |
|---|---|
| 11, 12 | 좌/우 어깨 |
| 23, 24 | 좌/우 엉덩이 |

### 지표

```
shoulderMid = (L11 + L12) / 2
hipMid      = (L23 + L24) / 2
```

**tilt (수직 대비 몸통 기울기)**

```
dx = shoulderMid.x - hipMid.x
dy = shoulderMid.y - hipMid.y
tilt = atan2(|dx|, |dy|) * 180/π
```

서 있으면 몸통이 세로라 `dy`가 크고 `dx`가 작아 tilt는 0°에 가깝다. 누우면 90°에 가까워진다. 정규화 좌표(0~1)를 쓰므로 카메라 거리와 무관하다.

**hipVelocity (엉덩이 하강 속도)**

```
hipVelocity = (hipMid.y - prevHipMid.y) / Δt    // 정규화 단위/초, 양수 = 하강
```

두 값 모두 지수이동평균(α=0.4)으로 스무딩한다. MediaPipe 랜드마크는 프레임마다 미세하게 떨리므로, 스무딩하지 않으면 velocity가 노이즈로 임계값을 넘나든다.

### 상태머신

정상 경로는 아래 한 줄이고, 나머지는 전부 STANDING으로 되돌아가는 취소 경로다.

```
STANDING ──속도──▶ FALLING ──자세──▶ FALLEN ──시간──▶ ALERTED ──▶ POST 1회
```

전이 규칙은 다음이 전부다. 위에서부터 순서대로 평가하고, 처음 일치하는 규칙만 적용한다.

| 현재 상태 | 조건 | 다음 상태 | 부수 효과 |
|---|---|---|---|
| 모든 상태 | 랜드마크 2초 이상 미검출 | `NO_PERSON` | — |
| `NO_PERSON` | 랜드마크 재검출 | `STANDING` | 속도 이력 초기화 |
| `STANDING` | `hipVelocity > FALL_VELOCITY` | `FALLING` | `fallingAt = now` 기록 |
| `FALLING` | `tilt > TILT_FALLEN` | `FALLEN` | `fallenAt = now` 기록 |
| `FALLING` | `now - fallingAt > FALLING_WINDOW` | `STANDING` | 급히 앉은 것으로 판단 |
| `FALLEN` | `tilt < TILT_UPRIGHT` | `STANDING` | 오탐지 취소, 전송 안 함 |
| `FALLEN` | `now - fallenAt > FALLEN_HOLD` | `ALERTED` | **낙상 확정** → `occurred_at = fallingAt` |
| `ALERTED` | `tilt < TILT_UPRIGHT` | `STANDING` | 재무장 |

**세 관문의 의도**

1. `STANDING → FALLING`은 **속도**로 건다. 침대에 천천히 눕거나 의자에 앉으면 하강 속도가 임계값에 못 미쳐 FALLING에 진입조차 하지 않는다. 오탐지 방어의 1차 관문이다.
2. `FALLING → FALLEN`은 **자세**로 건다. 빠르게 내려갔더라도 몸통이 서 있으면 급히 앉은 것이다. 1초 안에 수평에 도달해야 넘어진 것으로 본다.
3. `FALLEN → ALERTED`는 **시간**으로 건다. 5초 안에 일어나면 STANDING으로 되돌리고 아무것도 보내지 않는다. 스스로 일어난 사람 때문에 보호자를 깨우지 않기 위함이다.

**세부 규칙 및 경계 조건**

- `occurred_at`은 ALERTED 시각이 아니라 **FALLING 진입 시각**(`fallingAt`)이다. 보호자에게 실제로 넘어진 순간이 표시되어야 한다.
- `ALERTED`에서 다시 일어나야만 STANDING으로 재무장되므로, 누워 있는 동안 같은 낙상이 반복 전송되지 않는다. `ALERTED` 상태에서는 추가 POST가 발생하지 않는다.
- `TILT_UPRIGHT`(45°)와 `TILT_FALLEN`(60°) 사이의 15° 구간은 **의도적인 히스테리시스 밴드**다. `FALLEN` 상태에서 tilt가 이 구간에 있으면 어느 전이도 발동하지 않고 `FALLEN`을 유지하며 타이머는 계속 흐른다. 두 임계값을 하나로 합치면 경계에서 상태가 진동한다.
- `NO_PERSON`은 `FALLEN` 도중에도 발동한다. 즉 넘어지면서 프레임을 벗어나면 낙상이 전송되지 않는다. 알려진 한계이며 README에 명시한다.
- 첫 프레임에는 `prevHipMid`가 없으므로 `hipVelocity = 0`으로 둔다. `NO_PERSON`에서 복귀할 때도 마찬가지로 속도 이력을 초기화한다. 그러지 않으면 재검출 순간의 좌표 점프가 거대한 가짜 속도로 잡혀 즉시 오탐지가 난다.
- `Δt`의 단위는 초다. MediaPipe가 주는 타임스탬프는 밀리초이므로 변환에 주의한다.
- `confidence`는 낙상 확정 시점에 사용한 랜드마크 4개(11, 12, 23, 24)의 `visibility` 평균이다.

### 임계값

```js
const CONFIG = {
  FALL_VELOCITY: 0.45,   // 정규화 y단위/초
  TILT_UPRIGHT: 45,      // ° — 이 아래면 서 있음
  TILT_FALLEN: 60,       // ° — 이 위면 수평
  FALLING_WINDOW: 1000,  // ms — FALLING 유효 시간
  FALLEN_HOLD: 5000,     // ms — 미회복 확정 시간
  EMA_ALPHA: 0.4,
};
```

이 값들은 추정치다. 실제 웹캠으로 테스트하며 조정해야 하며, 조정 과정은 `context-notes.md`에 기록한다.

## 7. 웹 클라이언트 구조

```
web/
├── index.html      로그인
├── detect.html     감지 화면 (방 선택 → 시작)
├── css/
└── js/
    ├── detector.js   순수 로직: (랜드마크, 타임스탬프) → 상태 + 낙상 여부
    ├── pose.js       MediaPipe 초기화, 웹캠 프레임 루프
    ├── overlay.js    캔버스에 스켈레톤 그리기
    ├── api.js        fetch 래퍼, 토큰
    └── main.js       조립
```

`detector.js`는 브라우저 API를 하나도 쓰지 않는다. 따라서 Node에서 가짜 랜드마크 시퀀스로 단위 테스트할 수 있고, 브라우저는 같은 파일을 그대로 import한다. Vitest를 dev 의존성으로 추가하되 배포 코드는 순수 JS를 유지한다.

## 8. Flutter 앱

화면 3개, 상태관리는 `setState`. 공유 상태가 토큰 하나뿐이라 Provider/Riverpod은 과하다.

```
lib/
├── main.dart
├── api.dart            http 클라이언트 + 토큰
├── models.dart         FallEvent
├── notifications.dart  flutter_local_notifications 래퍼
├── poller.dart         5초 타이머 → 새 id 감지
└── screens/
    ├── login.dart
    ├── fall_list.dart
    └── fall_detail.dart
```

의존성: `http`, `flutter_local_notifications`, `shared_preferences`, `url_launcher`

**폴링 규칙**

- `fall_list`가 살아 있는 동안 5초마다 `GET /api/falls/`
- 응답의 최대 id > 저장된 id이면 새 이벤트에 대해 로컬 알림 후 저장값 갱신
- 최초 로그인 시에는 첫 응답의 최대 id를 알림 없이 저장한다 (기존 이벤트 알림 폭탄 방지)

**전화와 신고**

`url_launcher`의 `tel:` 스킴으로 다이얼러에 번호를 띄우는 데까지만 한다. 실제 발신은 사용자가 누른다. 119는 시연 중 실제 발신을 막기 위해 더미 번호 상수로 두고 코드에 이유를 주석으로 남긴다. 노인 연락처도 앱 내 상수다. 연락처 관리 화면은 범위 밖이다.

## 9. 오류 처리

| 상황 | 처리 |
|---|---|
| 웹캠 권한 거부 | 감지 페이지에 안내 문구, 재시도 버튼 |
| MediaPipe 모델 로드 실패 | 에러 표시, 감지 시작 차단 |
| 낙상 POST 실패 | 지수 백오프 3회 재시도 → 실패 시 화면 상단 빨간 배너 |
| 토큰 만료 / 401 | 토큰 폐기 후 로그인 화면으로 |
| 앱 폴링 실패 | 조용히 다음 주기 재시도, 3회 연속 실패 시 "연결 끊김" 배너 |

## 10. 테스트

**Django (pytest + pytest-django)**
- 인증 없이 `/api/falls/` 접근 → 401
- 남의 이벤트 조회 → 목록에 안 나옴
- 남의 이벤트 acknowledge → 404
- POST 시 `guardian`이 요청자로 강제되는지
- acknowledge가 `acknowledged_at`을 채우고, 두 번 호출해도 첫 시각 유지

**detector.js (Vitest)**
- 천천히 눕기 → 알림 없음 (FALLING 미진입)
- 빠르게 주저앉기 → 알림 없음 (tilt 미달)
- 빠르게 넘어져 3초 만에 일어남 → 알림 없음 (자가 회복)
- 빠르게 넘어져 5초 유지 → 낙상 1건, `occurred_at`이 FALLING 진입 시각
- 넘어진 채 10초 더 유지 → 여전히 1건 (중복 없음)
- 넘어졌다 일어났다 다시 넘어짐 → 2건

**Flutter**

`poller.dart`의 "새 id 판별" 로직만 단위 테스트한다. 위젯 테스트는 생략한다.

## 11. 작업 순서

| # | 단계 | 완료 확인 |
|---|---|---|
| 1 | Django 프로젝트 + `FallEvent` + 토큰 인증 + API | pytest 통과, `curl`로 로그인·등록·조회 |
| 2 | `detector.js` 상태머신 (TDD) | Vitest 6개 시나리오 통과 |
| 3 | 감지 페이지 (웹캠 → MediaPipe → 스켈레톤 → 상태 표시) | 브라우저에서 넘어져 보고 상태 전이 관찰 |
| 4 | 감지 페이지 ↔ Django 연결 | 실제로 넘어지면 DB에 행 생성 |
| 5 | Flutter 로그인 + 목록 + 상세 | 앱에서 DB의 이벤트가 보임 |
| 6 | 폴링 + 로컬 알림 + 확인/전화/신고 | 넘어지면 5초 내 에뮬레이터에 알림 |
| 7 | 임계값 튜닝 + README | 오탐지 없이 3회 연속 감지 성공 |

2번이 3번보다 먼저인 것이 중요하다. 상태머신을 웹캠 없이 완성해두면, 3번에서 문제가 생겼을 때 판정 로직과 랜드마크 품질 중 무엇이 원인인지 헷갈리지 않는다.

## 12. 범위 밖

의도적으로 제외한 것들이다. README에도 한계로 명시한다.

- **회원가입 화면** — 보호자 계정은 시드 데이터 / `createsuperuser`로 생성
- **방 등록·관리 화면** — 방은 감지 페이지의 고정 선택지
- **연락처 관리** — 노인 연락처와 신고 번호는 상수
- **낙상 POST 유실 대비 큐잉** — 재시도 3회 후 포기. 실제 제품이라면 localStorage 큐가 필요
- **백그라운드 알림** — 폴링 방식이라 앱이 백그라운드면 멈춤. 실제 제품이라면 FCM 필요
- **프레임 밖 낙상** — 넘어지며 화면을 벗어나면 감지 불가
- **다중 인물** — `numPoses: 1`, 독거 전제
- **실시간 방 상태 대시보드** — 웹캠이 하나라 의미 없음
