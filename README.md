# 노인 낙상 감지 시스템

혼자 사는 노인의 낙상을 카메라로 감지해 보호자에게 즉시 알린다. **영상은 기기를 벗어나지 않는다.**

같은 와이파이(LAN) 안에서 전부 실행한다 — 백엔드와 감지 페이지는 Mac에서 띄우고, 보호자 앱은 폰·PC 브라우저 어느 쪽에서든 붙는다.

## 사생활 보호

이 프로젝트의 출발점은 "감시 카메라를 집 안에 두는 거부감"이다. 그래서 영상을 서버로 보내지 않는 것을 **구조로** 보장했다.

- MediaPipe Pose를 **브라우저에서** 실행한다. 웹캠 영상은 브라우저 안에서 관절 좌표가 된다.
- **관절 좌표조차 서버로 보내지 않는다.** 낙상이 확정된 순간에만 `{room_name, room_number, occurred_at, confidence}` 4개 필드가 1회 전송된다.
- 화면에도 원본 영상을 표시하지 않는다. 검은 배경 위 스켈레톤만 그린다. 디버그용 영상 토글도 없다.
- 마이크는 평상시 꺼져 있다. 낙상이 확정된 응급 구간에서만 켜지고, 해제·신고와 함께 다시 꺼진다.

## 구조

```
[웹캠] → 브라우저 (web/) — 감지 페이지
           │  MediaPipe로 랜드마크 추출 → 상태머신 판정
           │  ※ 영상·랜드마크 전부 브라우저 밖으로 안 나감
           │  ※ 전송 실패분은 localStorage 큐에 보관했다가 재전송
           │
           └─ 낙상 확정 시 1회 + 20초 무응답 시 119 신고 재-POST 1회
              POST /api/falls/  (Token 헤더, 재전송·신고 중복은 서버가 흡수·병합)
                      │
             [Spring Boot 4.1 + PostgreSQL 18]  (backend/)
                      │
             GET /api/falls/ ← 5초 폴링
                      │
             [Flutter 앱 (app/)]
              iOS · Android · 웹 브라우저
              새 낙상 → 사고 발생 창 + 로컬 알림
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

임계값은 2026-07-17에 20시행 8899프레임을 실측해 검증했다 — 넘어지기 5/5 감지, 눕기·앉기·서 있기 11/11 오탐지 없음. 상수는 `web/js/detector.js`의 `CONFIG` 한 곳에 모여 있어 카메라 배치에 맞춰 조정할 수 있고, `web/js/tuning.js`의 튜닝 패널이 hipV·tilt 실측값을 실시간으로 보여준다. 측정 원본은 `docs/tuning/`에 CSV로 남아 있다.

## 응급 음성 확인 · 119 자동 신고

낙상이 확정되면 감지 페이지가 스스로 상태를 확인한다.

| 시각 | 동작 |
|------|------|
| 0초 | 낙상 확정 → 보호자에게 전송 |
| 10초 | 스피커로 "괜찮으세요?" 질문 |
| ~20초 | 대답을 들음 — "괜찮아"면 해제하고 앱에 "괜찮다고 말함"으로 표시 |
| 20초 | 무응답이면 119 신고를 기록(`reported_119_at`)하고 앱에 배지 표시 |

브라우저 내장 음성 인식(Web Speech API)을 쓴다. 자기 목소리를 되받지 않도록 재생 중에는 청취를 멈추고, 상태머신에서 한 번 더 막는다. 신고 기록은 **새 엔드포인트 없이** 같은 `POST /api/falls/`를 다시 보내 서버가 첫 값을 보존하며 병합한다.

## 보호자 앱

Flutter 하나로 iOS · Android · 웹 브라우저에서 같은 화면이 뜬다. 화면은 12개다.

- **시작 흐름** — 스플래시 → 시작 → 로그인/회원가입
- **홈** — 미확인·최근 알림, 방 추가 배너
- **하단 탭** — 홈 · 방 관리(2열 카드로 추가/수정/삭제) · 프로필
- **알림** — 목록과 상세. 상세에서 돌봄 대상자 전화, 119 긴급 신고, 기록 삭제
- **사고 발생 창** — 새 낙상이 오면 화면 위로 뜨고 확인 버튼으로만 닫힌다. 여러 건이면 순차로 표시하며, 창에서 바로 전화·119를 걸 수 있다
- **설정** — 다크모드, 화면 크기 배율, 알림 토글

목록·홈 타일에는 상태 배지가 붙는다(`119 신고됨` > `괜찮다고 말함` > `확인함`/`미확인`). 다크모드는 앱 전 화면에 적용된다. 화면 캡쳐는 `docs/screenshots/`에 있다.

## 실행 방법

한 대의 Mac에서 전부 띄우고, 폰은 같은 와이파이로 접속한다. 터미널 3개가 필요하다.

### 1. Spring Boot (`:8000`)

```bash
cd backend
createdb fall_detection        # 최초 1회 (postgresql@18 서비스는 이미 실행 중)
./gradlew bootRun              # 0.0.0.0:8000 — 같은 와이파이 기기의 접속을 받는다
```

### 2. 감지 페이지 (`:5500`)

```bash
cd web
python3 -m http.server 5500
```

`http://127.0.0.1:5500`에서 로그인(첫 사용이면 회원가입) → 방 선택(없으면 그 자리에서 추가) → 감지 시작 → 카메라·마이크 권한 허용.

**감지 페이지는 Mac에서 연다.** `getUserMedia`(카메라)가 요구하는 보안 컨텍스트를 `localhost`가 충족하므로 HTTPS 없이 동작한다. API 주소는 접속한 호스트를 그대로 따라가므로(`web/js/api.js`) 별도 설정이 없다. Mac IP는 `ipconfig getifaddr en0`으로 확인한다.

### 3. Flutter 앱

```bash
cd app
flutter pub get
flutter devices                               # 연결된 기기·시뮬레이터 확인
flutter run                                   # iOS 시뮬레이터
flutter run -d <에뮬레이터 id>                # Android 에뮬레이터 — 보통 emulator-5554
flutter run --dart-define=API_HOST=<Mac IP>   # 실기기 — 같은 와이파이의 Mac IP
flutter run -d chrome                         # 웹 — 크롬으로 실행
```

시뮬레이터·에뮬레이터는 서버 주소가 자동으로 잡힌다. iOS 시뮬레이터는 `127.0.0.1:8000`, Android 에뮬레이터는 `10.0.2.2:8000`이다(에뮬레이터 안에서 `127.0.0.1`은 호스트 맥이 아니라 에뮬레이터 자신이다). 실기기는 양쪽 다 같은 와이파이에 물린 Mac의 IP를 `API_HOST`로 넘긴다(`app/lib/api.dart`). 릴리즈 설치도 같다 — `flutter run --release --dart-define=API_HOST=<Mac IP>`.

웹은 페이지를 연 호스트가 곧 서버 주소다(크롬 실행은 `localhost:8000`, `API_HOST`로 바꿀 수 있다). 배포는 `cd app && flutter build web` — `app/build/web`의 정적 파일을 아무 정적 서버로 **http**로 서빙하면 된다(서브패스에 올릴 때는 `--base-href`를 함께 준다). 웹에서는 OS 알림 대신 인앱 사고 발생 창이 알림 역할을 한다.

에뮬레이터 id는 환경마다 다르니 `flutter devices`로 확인한다.

## API

토큰 헤더(`Authorization: Token <키>`) 인증이다. 로그인·가입·헬스체크만 공개다.

| 메서드 | 경로 | 하는 일 |
|--------|------|---------|
| `POST` | `/api/auth/signup/` | 회원가입 — 가입 즉시 토큰 반환 |
| `POST` | `/api/auth/login/` | 로그인 |
| `GET` | `/api/falls/` | 내 낙상 목록 (최신순) |
| `POST` | `/api/falls/` | 낙상 등록 — 중복은 유니크 제약이 흡수(201/200), 119·괜찮음 필드는 병합 |
| `POST` | `/api/falls/{id}/acknowledge/` | 확인 처리 |
| `DELETE` | `/api/falls/{id}/` | 확인한 기록 삭제 |
| `GET` `POST` `GET/PUT/PATCH/DELETE` | `/api/rooms/`, `/api/rooms/{id}/` | 방 관리 |
| `GET` `PUT` | `/api/profile/` | 보호자·돌봄 대상자 정보 |

낙상 데이터는 계정별로 격리된다 — 조회·수정·삭제가 전부 `findByIdAndGuardianId`를 거친다.

## 테스트

```bash
cd backend && ./gradlew test    # 37개 — 인증·소유권·방·프로필·전송 멱등성·기록 삭제·119/괜찮음 병합
                                #        (fall_detection_test DB 필요: createdb fall_detection_test)
cd web     && npm test          # 30개 — 상태머신 시나리오(낙상 12·음성 에스컬레이션 12)·오프라인 큐 6
cd app     && flutter test      # 76개 — 화면·모델·폴링·알림·다크모드·사고 발생 창·전화 발신
```

상태머신 테스트가 이 프로젝트 테스트의 핵심이다. 가짜 랜드마크 시퀀스로 "천천히 눕기 → 알림 없음", "3초 만에 일어남 → 알림 없음", "5초 유지 → 1건" 같은 시나리오를 웹캠 없이 검증한다.

서버를 띄운 채 도는 E2E도 따로 있다. 실행 조건은 [docs/manual-verification.md](docs/manual-verification.md) 8절에 있다.

```bash
cd web     && npm run test:e2e:sw     # 서비스 워커 캐시 축출
cd web     && npm run test:e2e:301    # 캐시된 301 처리
cd app     && flutter test integration_test/fall_delete_test.dart -d <UDID>
cd scripts/e2e && node queue-e2e.mjs  # 오프라인 큐 재전송
```

## 문서

- [백엔드 구현 설명](docs/backend-architecture.html) — Spring Boot 백엔드가 어떻게 만들어졌고 어떻게 동작하는가
- [수동 검증 절차](docs/manual-verification.md) — 사람이 직접 밟는 확인 항목
- 설계·구현 계획 — [`docs/superpowers/specs/`](docs/superpowers/specs/), [`docs/superpowers/plans/`](docs/superpowers/plans/)
  - 감지 파이프라인 (2026-07-17) · 제품 완성도 라운드 (2026-07-23) · 백엔드 Spring Boot 교체 (2026-07-24)
  - 낙상 기록 삭제 · 음성 확인/119 · 괜찮음 표시 · Android 지원 (2026-07-27)
  - 다크모드·사고 발생 창 (2026-07-28) · Flutter 웹 지원 · 사고 창 전화/119 (2026-08-09)
- [화면 캡쳐](docs/screenshots/) · [임계값 실측 데이터](docs/tuning/)
