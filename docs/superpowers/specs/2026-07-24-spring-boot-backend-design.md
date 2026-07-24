# 백엔드 Java Spring Boot 교체 설계

2026-07-24. Django 백엔드를 Java Spring Boot로 전면 교체하는 라운드다. 목적은 학습·포트폴리오 —
한국 실무 표준 스택(Spring Security + JPA)을 정면으로 다루고, 리뷰어에게 익숙한 구조로 만든다.
브레인스토밍 결정 기록이며 구현 계획의 입력이 된다.

## 1. 범위와 결정

1. **완전 교체** — `backend/`(Django·SQLite·venv)를 삭제하고 같은 자리에 Spring Boot 프로젝트를 만든다.
   기존 계정·낙상 기록은 버린다(회원가입 재진행). git 히스토리에는 남는다.
2. **클라이언트 무수정이 최우선 계약** — 웹(`web/`)·Flutter 앱(`app/`)은 한 줄도 고치지 않는다.
   경로(끝 슬래시 포함)·상태 코드·snake_case 필드·에러 JSON 형태·`Authorization: Token <key>` 헤더까지
   전부 그대로여야 한다. 이 계약의 검수 수단이 테스트다(9절).
3. **DB는 PostgreSQL** — 이 Mac에 Homebrew `postgresql@18`이 이미 서비스로 실행 중이라 설치 부담이 없고,
   실무 DB를 직접 다루는 경험이 목적에 맞는다. DB 이름 `fall_detection`, 최초 1회 `createdb`만 필요하다.
4. **표준 레이어드 아키텍처** — controller/service/repository/domain 계층. 패키지-바이-피처는
   도메인 4개 규모에 이점이 작아 제외, Security·JPA를 생략하는 미니멀 구성은 학습 목적에 안 맞아 제외.

범위 밖: 클라이언트 수정, 기존 데이터 이전, Spring 버전 아키텍처 문서(`docs/backend-architecture.html`의
후속), 관리자 화면, JWT(9절 하단 참고).

## 2. 기술 스택

| 항목 | 선택 | 근거 |
|------|------|------|
| Java | 21 (Temurin, 설치됨) | LTS |
| Spring Boot | 스캐폴딩 시점의 최신 안정판 (4.x 예상) | start.spring.io 기준으로 확정 |
| 빌드 | Gradle(Groovy DSL) + 래퍼 | Gradle 미설치 환경에서도 `./gradlew`로 동작 |
| 인증 | Spring Security + 커스텀 토큰 필터 | DRF TokenAuthentication 등가 구현 |
| ORM | Spring Data JPA (Hibernate) | 표준 |
| 마이그레이션 | Flyway (`V1__init.sql`) | Django migrations 등가물. 멱등성이 의존하는 유니크 제약 이름을 SQL로 결정적으로 지정 |
| 웹 푸시 | `nl.martijndwars:web-push` + BouncyCastle | 자바 표준 선택지. 구현 시점에 유지보수 상태 확인, 필요 시 동급 대체 |
| 테스트 | JUnit 5 + MockMvc | 로컬 Postgres `fall_detection_test` DB 사용 |

## 3. 프로젝트 구조

```
backend/
  src/main/java/com/weniv/falls/
    controller/   AuthController, FallController, RoomController,
                  ProfileController, PushController, HealthController
    service/      AuthService, FallService, RoomService, ProfileService, PushService
    repository/   GuardianRepository, AuthTokenRepository, FallEventRepository,
                  RoomRepository, GuardianProfileRepository, PushDeviceRepository
    domain/       Guardian, AuthToken, FallEvent, Room, GuardianProfile, PushDevice
    dto/          요청·응답 record
    config/       SecurityConfig, CorsConfig, AsyncConfig
    error/        GlobalExceptionHandler
  src/main/resources/
    application.yml
    db/migration/V1__init.sql
  src/test/java/com/weniv/falls/   (9절의 포팅 테스트)
```

서버 포트는 기존과 같은 `8000`, 바인딩 `0.0.0.0`(같은 와이파이 기기 접속). CORS 전 오리진 허용,
CSRF 비활성(토큰 헤더 인증), 세션 STATELESS. 루트 `/`는 헬스체크
`{"status": "ok", "service": "fall-detection-backend"}`를 그대로 반환한다.

## 4. 데이터 모델

Django 모델의 1:1 이식이다. 유니크 제약 이름은 Flyway SQL에서 지정한다.

```
Guardian        id · username(varchar 150, unique) · password(BCrypt 해시) · created_at
AuthToken       key(varchar 40, PK — 40자 hex 랜덤) · guardian(unique FK) · created_at
                DRF authtoken 등가 — 보호자당 1개, 만료 없음. "한 번 로그인하면 유지" 동작 보존.
FallEvent       id · guardian FK · room_name(varchar 20) · room_number(smallint)
                · occurred_at(timestamptz) · created_at · confidence(double)
                · acknowledged_at(timestamptz, null)
                unique (guardian, room_name, room_number, occurred_at) = uniq_fall_dedup
Room            id · guardian FK · name(varchar 20) · number(smallint)
                unique (guardian, name, number) = uniq_room_per_guardian
GuardianProfile id · guardian(unique FK) · elder_phone(varchar 20, 기본 "")
                접근 시 get-or-create.
PushDevice      id · guardian FK · kind("webpush") · token(text, unique) · created_at
```

- FallEvent의 방 정보는 문자열 스냅샷 유지(Room FK 아님) — 방을 지워도 과거 기록이 안 깨진다.
- `uniq_fall_dedup`이 오프라인 큐 재전송 멱등성의 근거다(5절 POST 규칙).
- 시각은 전부 UTC로 저장한다(timestamptz).

## 5. API 계약 — 전 엔드포인트

기존과 동일해야 한다. 표의 형태가 곧 수용 기준이다.

```
POST /api/auth/login/       {username, password} → 200 {"token"} / 실패 400
POST /api/auth/signup/      {username, password} → 201 {"token"} / 400 {"username": [...]} 또는 {"password": [...]}
GET  /api/falls/            → 200 [FallEvent…] 최신순(id desc). 요청자 것만.
POST /api/falls/            {room_name, room_number, occurred_at, confidence}
                            → 신규 201 + 비동기 푸시 / 중복(uniq_fall_dedup 일치) 200 기존 행 + 푸시 없음
                            / 검증 실패 400. body의 guardian 값은 무시하고 요청자로 강제.
POST /api/falls/{id}/acknowledge/ → 200. 첫 호출만 acknowledged_at 기록(멱등). 남의 것 404.
GET  /api/rooms/            → 200 [Room…] name, number 순 정렬
POST /api/rooms/            {name, number} → 201 / 중복 400
GET|PUT|PATCH|DELETE /api/rooms/{id}/ → 200/200/200/204. PATCH는 부분 수정(웹은 {name}만 보낸다).
                            중복 400, 남의 것 404.
GET  /api/profile/          → 200 {"elder_phone"} (없으면 빈 값으로 생성)
PUT  /api/profile/          {elder_phone} → 200
POST /api/push/devices/     {kind: "webpush", token} → 201. token이 다른 계정에 있으면 현 사용자로
                            이전(계정 전환 케이스). kind가 webpush 외면 400.
DELETE /api/push/devices/   body {token} → 항상 204 (없는 토큰이어도 — 로그아웃을 막지 않는다)
GET  /api/push/vapid-key/   → 200 {"key"} / 키 미설정 503 {"detail": "웹 푸시가 설정되지 않았습니다."}
GET  /                      → 200 헬스체크 JSON
```

직렬화 규칙.

- FallEvent 응답 필드는 `id, room_name, room_number, occurred_at, created_at, confidence,
  acknowledged_at` 순서 무관, snake_case 고정. Room은 `id, name, number`.
- 시각 출력은 UTC ISO-8601 `Z` 표기(`2026-07-23T03:00:00Z`). 소수 초는 있어도 된다(양쪽 클라이언트
  파서가 수용). 입력은 `+09:00` 같은 오프셋도 받아 UTC로 변환 저장한다.
- `room_number`·`number`는 0 이상 정수(Django PositiveSmallIntegerField 등가, 0~32767).
- `DELETE /api/push/devices/`는 JSON body를 읽는다(비표준이지만 기존 계약).

## 6. 인증

- `OncePerRequestFilter`가 `Authorization: Token <key>`를 읽어 AuthToken 테이블과 대조, 성공 시
  SecurityContext에 보호자를 넣는다. 실패·부재 응답은 401 `{"detail": "..."}`(메시지 문구는 자유,
  형태 고정 — 클라이언트는 상태 코드만 본다).
- `permitAll`은 `/api/auth/login/`, `/api/auth/signup/`, `/` 셋뿐. 나머지는 인증 필수.
- 로그인은 username 조회 + BCrypt 대조 후 토큰 get-or-create. 회원가입은 검증 통과 시 생성 + 토큰
  즉시 발급(별도 로그인 불필요 동작 보존).
- 가입 검증은 Django 규칙과 동등, 메시지는 한국어.
  - username — 필수, 150자 이하, 영숫자와 `@.+-_`만, 중복 거부.
  - password — 8자 이상, 전부 숫자 거부, 흔한 비밀번호 거부(소형 내장 목록. Django의 2만 개 목록
    전체 이식은 하지 않는다 — 대표 수백 개면 학습 목적에 충분).

## 7. 웹 푸시

- best-effort 원칙 유지 — 발송 경로의 어떤 예외도 API 응답에 영향을 주지 않는다. 앱 폴링이 안전망.
- `POST /api/falls/`가 201일 때만 `@Async` 스레드풀에서 보호자의 모든 PushDevice로 발송한다.
  페이로드는 기존과 동일한 `{"type": "fall", "id", "room_name", "room_number", "occurred_at",
  "confidence"}` — `web/sw.js`가 이 형태를 파싱한다.
- 푸시 서비스가 404/410을 주면 만료 구독이므로 그 자리에서 삭제. 그 외 실패는 로그만 남긴다.
- `VAPID_PRIVATE_KEY`(base64url 32바이트 스칼라)·`VAPID_SUBJECT` 환경변수 미설정이면 발송·공개키
  엔드포인트 모두 조용히 비활성(503은 vapid-key만). 공개키는 BouncyCastle EC 연산으로 개인키에서
  파생한다 — 기존과 같이 서버에 공개키를 따로 두지 않는다.
- 키 생성 안내는 README에서 Python 스니펫 대신 `npx web-push generate-vapid-keys`로 교체한다
  (출력의 private key가 그대로 `VAPID_PRIVATE_KEY` 형식과 호환).

## 8. 에러 처리

`GlobalExceptionHandler` 하나가 DRF 호환 형태로 변환한다. 웹·앱의 `firstErrorMessage()`
(`{필드: [메시지…]}`의 첫 값)가 그대로 동작해야 한다.

- 필드 검증 실패 → 400 `{"필드명": ["한국어 메시지", …]}`
- 방 중복 → 400 `{"non_field_errors": ["같은 이름과 번호의 방이 이미 있습니다."]}` — 문자열까지 고정
  (사전 검사로 잡고, 경합으로 유니크 제약에 걸린 경우도 같은 400으로 변환)
- 인증 실패 → 401, 소유권 밖 리소스 → 404, 둘 다 `{"detail": "..."}` — 남의 리소스는 guardian 조건을
  건 조회로 존재 자체가 드러나지 않게 한다
- 낙상 중복 POST는 에러가 아니라 200 정상 경로다(5절)

## 9. 테스트

성공 기준 세 겹이다.

1. **포팅 테스트** — 기존 pytest 32개를 JUnit 5 + MockMvc로 전부 1:1 포팅한다. 인증(401)·로그인·
   가입(토큰 즉시 유효, 중복·약한 비밀번호 400)·목록 격리·최신순·guardian 강제·acknowledge 멱등과
   404·방 CRUD·중복 400·경합 안전망·프로필 get-or-create·푸시 기기 등록/계정 이전/해제/kind 검증·
   발송(키 미설정 스킵, 만료 구독 삭제, 실패 무해화)·vapid-key 200/503·낙상 멱등 POST(중복 200,
   행 불변, 푸시 1회/0회). 발송은 목으로 막는다.
   테스트 DB는 로컬 Postgres `fall_detection_test` — 실 DB와 같은 엔진이라 dialect 차이로 인한
   거짓 통과가 없다.
2. **클라이언트 회귀** — `web/ npm test` 20개, `app/ flutter test` 4개가 무수정으로 통과.
3. **E2E** — 서버를 실제로 띄우고 `scripts/e2e`의 브라우저 E2E(오프라인 큐 재전송·웹 푸시)를 재실행.

JWT를 쓰지 않는 이유 — 클라이언트에 갱신 로직이 없어 만료가 생기면 "로그인 유지" UX가 깨진다.
DRF와 같은 무만료 불투명 토큰이 계약 보존에 정확히 맞는다.

## 10. 실행·문서·삭제 범위

실행(README 갱신 내용).

```bash
cd backend
createdb fall_detection        # 최초 1회 (postgresql@18 서비스는 이미 실행 중)
./gradlew bootRun              # :8000
```

푸시를 켤 때는 기존처럼 `VAPID_PRIVATE_KEY`·`VAPID_SUBJECT`를 환경변수로 붙인다. 감지 페이지·앱
실행법은 변화 없다.

- README 갱신 — 구조도(`Django + SQLite` → `Spring Boot + PostgreSQL`), 백엔드 실행법, 테스트 실행법
  (`./gradlew test`), VAPID 키 생성 스니펫.
- `docs/backend-architecture.html` 삭제 — Django 코드 설명 문서라 코드와 함께 제거, README 링크도 제거.
- `backend/` 기존 내용 전체 삭제(`db.sqlite3`·`.venv`·pytest 설정 포함).
- 커밋은 의미 단위 — 스캐폴딩 → 도메인·마이그레이션 → 인증 → API → 푸시 → 테스트 → Django 제거·문서
  갱신 순 예상(구현 계획에서 확정).
