# 노인 낙상 감지 시스템 — 체크리스트

설계: [docs/superpowers/specs/2026-07-17-fall-detection-design.md](docs/superpowers/specs/2026-07-17-fall-detection-design.md)
구현 계획: [docs/superpowers/plans/2026-07-17-fall-detection.md](docs/superpowers/plans/2026-07-17-fall-detection.md)

아래는 설계 기준 체크리스트다. 실제 구현은 계획 문서의 Task 1~16을 따르고, 각 태스크를 끝낼 때 여기 해당 항목을 함께 체크한다.

## 0. 설계

- [x] 요구사항 브레인스토밍
- [x] 설계 문서 작성
- [x] 구현 계획 작성 (writing-plans) — Task 16개, 계획 작성 중 검증한 내용은 context-notes.md 참고

## 1. Django 백엔드

- [x] 프로젝트 생성 (`backend/`, config + falls 앱)
- [x] `FallEvent` 모델 + 마이그레이션
- [x] DRF 토큰 인증 설정 + `POST /api/auth/login/`
- [x] `django-cors-headers` 설정 (`:5500` 허용)
- [x] `POST /api/falls/` — guardian을 요청자로 강제
- [x] `GET /api/falls/` — 본인 이벤트만, 최신순
- [x] `POST /api/falls/<id>/acknowledge/`
- [x] pytest 7개 시나리오 통과 (계획 진행 중 Task 2~4에 걸쳐 5개 → 7개로 늘었다)
- [x] `curl`로 로그인 → 등록 → 조회 확인 (Task 4에서 실제로 수행, task-4-report.md 참고)

## 2. detector.js 상태머신 (TDD)

- [x] Vitest 설정
- [x] 가짜 랜드마크 시퀀스 생성 헬퍼
- [x] 테스트: 천천히 눕기 → 알림 없음
- [x] 테스트: 빠르게 주저앉기 → 알림 없음
- [x] 테스트: 3초 만에 일어남 → 알림 없음
- [x] 테스트: 5초 유지 → 낙상 1건, `occurred_at` = FALLING 진입 시각
- [x] 테스트: 10초 더 유지 → 여전히 1건
- [x] 테스트: 넘어짐 → 일어남 → 다시 넘어짐 → 2건
- [x] `detector.js` 구현 (브라우저 API 미사용)
- [x] 7개 시나리오 전부 통과 (Task 6에서 NO_PERSON 재검출 시나리오가 추가돼 6개 → 7개)

## 3. 감지 페이지

- [x] `index.html` 로그인 화면
- [x] `detect.html` 방 선택 (안방/부엌/거실/화장실 + 방 번호)
- [x] `pose.js` — MediaPipe PoseLandmarker 초기화, 웹캠 루프
- [x] `overlay.js` — 검은 배경 + 스켈레톤만 (원본 영상 미표시)
- [x] 현재 상태 화면 표시 (STANDING/FALLING/FALLEN/ALERTED/NO_PERSON)
- [x] 웹캠 권한 거부 처리
- [x] 모델 로드 실패 처리
- [x] 브라우저에서 넘어져 보고 상태 전이 관찰 — 3차 실측에서 STANDING→FALLING→FALLEN→ALERTED 전이 확인 (context-notes.md 3차)

## 4. 감지 페이지 ↔ Django

- [x] `api.js` — fetch 래퍼 + 토큰 (localStorage)
- [x] 로그인 → 토큰 저장 → `detect.html` 이동
- [x] 낙상 확정 시 `POST /api/falls/`
- [x] 지수 백오프 3회 재시도
- [x] 실패 시 빨간 배너
- [x] 401 → 토큰 폐기 후 로그인 화면
- [x] 실제로 넘어지면 DB에 행 생성 확인 — 3차에서 POST 4건(id 2~5)이 DB에 도달함 (context-notes.md 3차)

## 5. Flutter 앱 (기본)

- [x] 프로젝트 생성 (`app/`)
- [x] 의존성 추가 (http, flutter_local_notifications, shared_preferences, url_launcher)
- [x] `models.dart` — FallEvent
- [x] `api.dart` — 토큰 저장/헤더
- [x] `login.dart`
- [x] `fall_list.dart` — 방·시각·처리상태
- [x] `fall_detail.dart`
- [x] 앱에서 DB의 이벤트가 보임 — 실기기(iPhone, iOS 26.5) 로그인 후 낙상 목록 6건 표시 확인

## 6. 폴링 + 알림 + 동작

- [x] `poller.dart` — 5초 타이머, 최대 id 비교
- [x] 최초 로그인 시 알림 없이 id만 저장
- [x] `poller.dart` 새 id 판별 단위 테스트
- [x] `notifications.dart` — 로컬 알림
- [x] 3회 연속 폴링 실패 → "연결 끊김" 배너
- [x] 확인함 → `POST acknowledge`
- [x] 전화 (`tel:` 상수)
- [x] 신고 (더미 번호 + 이유 주석)
- [x] 넘어지면 5초 내 알림 확인 — 실기기(iPhone)에서 이벤트 주입 후 5초 폴링으로 "안방 1에서 낙상 감지" 배너 표시 (context-notes.md "실기기 알림 검증")

## 7. 마무리

- [x] 실제 웹캠으로 임계값 튜닝 (조정 내역은 context-notes.md에) — 4세션 실측(1~4차), CONFIG 7개 값 유지 확인 (context-notes.md "임계값 튜닝 기록")
- [x] 오탐지 없이 3회 연속 감지 성공 — 3차에서 낙상 4회 연속 감지·해당 구간 오탐지 없음. 단 배치 오탐지 여유는 미확정 (context-notes.md 4차·README 한계)
- [x] README — 실행 방법, 아키텍처, 사생활 보호 설명
- [x] README — 범위 밖 / 한계 명시 (설계 문서 12절)

## 8. 배포 (2026-07-18) — 2026-07-24 제거

Render(백엔드)·GitHub Pages(감지 페이지) 배포를 준비했으나, 2026-07-24 **배포하지 않기로 결정**하고 관련 코드·설정·문서(render.yaml, GitHub Actions 워크플로, build.sh, DEPLOYMENT.md, deploy-guide.html, 루트 리다이렉트 등)를 모두 제거했다. 같은 와이파이(LAN) 실행 전용이다 — 실행 방법은 README. HTTPS가 전제였던 아이폰 홈 화면 PWA 푸시도 함께 범위 밖이 됐다. 경위는 context-notes.md "배포 제거".

- [x] ~~Android 릴리즈 매니페스트 INTERNET 권한~~ — 2026-07-24 Android 지원 제거로 소멸 (12절)

## 9. 회원가입 (2026-07-18)

- [x] `POST /api/auth/signup/` — username/password, 기존 비밀번호 검증기 적용, 가입 즉시 토큰 반환
- [x] pytest 3개 추가 (성공·중복 아이디·약한 비밀번호) — 총 10개
- [x] 검증 에러 메시지 한국어화 (`LANGUAGE_CODE = 'ko'`)
- [x] 웹 `signup.html` + 로그인 화면과 상호 링크
- [x] 앱 `signup.dart` + 로그인 화면에서 이동
- [x] 실서버 E2E — 가입 → 토큰으로 목록 200, 중복 가입 400 확인

## 10. 발표자료 (2026-07-18)

- [x] 제주 노인 문제 기사 검색 + 헤드리스 Chrome 캡쳐 5건 (고령화 2·독거/고독사 2·낙상 1)
- [x] 발표에 인용한 수치를 기사 원문·KDI에서 재확인 (추락 사망 1,802명, 72.5% 집 안, 고독사 증가율 43.6% 등)
- [x] `pre.html` 작성 — 14장 슬라이드, 기사 캡쳐 base64 인라인, 차트·다이어그램 SVG 자작
- [x] 헤드리스 Chrome으로 14장 전수 렌더링 검증 (레이아웃 깨짐 4건 수정 후 재확인)

## 11. 제품 완성도 라운드 — 푸시·오프라인 큐·방/연락처 관리 (2026-07-23)

설계: [docs/superpowers/specs/2026-07-23-product-completeness-design.md](docs/superpowers/specs/2026-07-23-product-completeness-design.md)
구현 계획: [docs/superpowers/plans/2026-07-23-product-completeness.md](docs/superpowers/plans/2026-07-23-product-completeness.md)

- [x] 설계 문서 작성
- [x] 구현 계획 작성 (writing-plans) — Task 16개, 결정 사항은 context-notes.md "제품 완성도 라운드 계획" 참고
- [x] 백엔드 (Task 1~6) — 모델 3개, 방·프로필·기기 API, 푸시 모듈, 멱등 POST. pytest 33개 통과 (계획 32개에서 1개 늘었다)
- [x] 감지 페이지 (Task 7~9) — 오프라인 큐(TDD), 큐 통합, 방 선택 연동. vitest 20개 통과 (다중 탭 flush 경합 등이 추가돼 계획 15개에서 늘었다)
- [x] 보호자 페이지 (Task 10~11) — guardian.html, 웹 푸시, PWA
- [x] Flutter (Task 12~15) — 모델·API, 설정 화면, FCM, 알림 소스 단일화. flutter test 7개 통과
- [x] 배포·문서 (Task 16) — render.yaml 환경변수 3개, DEPLOYMENT 푸시 절, README 갱신 (2026-07-24 배포 제거로 render.yaml·DEPLOYMENT.md는 삭제, 푸시 절차는 README로 이관)
- ~~수동 준비물 — Firebase 콘솔에서 google-services.json과 서비스 계정 키 발급~~ — 2026-07-24 Android 지원 제거로 폐기 (12절)

### 검증 라운드 (2026-07-24)

절차와 함정은 context-notes.md "E2E 검증 라운드", 재실행 방법은 [scripts/e2e/README.md](scripts/e2e/README.md).

- [x] 감지 페이지 오프라인→온라인 큐 재전송 브라우저 E2E — 실제 Chrome에서 8개 체크 통과 (`scripts/e2e/queue-e2e.mjs`)
- [x] VAPID 키 생성(절차는 현재 README "푸시 알림 (선택)" 절) + 데스크톱 브라우저 웹 푸시 E2E — 구독→발송→서비스 워커 알림 표시, 9개 체크 통과, 헤드리스에서도 실수신 (`scripts/e2e/push-e2e.mjs`)
- [x] iOS 시뮬레이터 첫 기동 — Firebase SwiftPM이 iOS 15를 요구해 배포 타깃 13.0→15.0 인상 후 빌드 성공. iPhone 17 Pro(26.5)에서 실행, 알림 권한 다이얼로그 표시, 7분+ 생존·크래시 리포트 없음
- ~~Android 실기기/에뮬레이터 백그라운드 FCM 수신~~ — 2026-07-24 Android 지원 제거로 폐기 (12절)

## 12. Android 지원 제거 (2026-07-24)

Android에서 실행하지 않기로 결정 — Android 플랫폼 디렉터리와, Android만을 위해 존재하던 FCM 스택 전체를 제거했다. 경위는 context-notes.md "Android 지원 제거".

- [x] `app/android/` 삭제, `.metadata`·`.gitignore`의 android 항목 정리
- [x] 앱에서 FCM 제거 — push.dart·firebase 의존성 삭제, notifiableFromPolling 제거(폴링이 항상 알림)
- [x] 백엔드에서 FCM 제거 — `_send_fcm`·firebase_admin·`FIREBASE_SERVICE_ACCOUNT` 삭제, PushDevice.kind는 webpush만 (마이그레이션 0003)
- [x] 문서 정리 — README에서 Android·FCM 제거, docs/firebase-setup.html 삭제, 과거 설계/플랜 문서에 제거 공지
- [x] 검증 — flutter analyze 클린, flutter test 4개, backend pytest 32개, iOS 시뮬레이터 빌드 성공

## 13. 백엔드 Spring Boot 교체 (2026-07-25)

Django 백엔드를 Java 21 + Spring Boot 4.1.0 + PostgreSQL 18로 완전 교체 — 클라이언트 무수정, API 계약(경로·상태 코드·snake_case·고정 문자열 2개) 보존. 설계는 docs/superpowers/specs/2026-07-24-spring-boot-backend-design.md, 계획은 docs/superpowers/plans/2026-07-25-spring-boot-backend.md, 경위는 context-notes.md "백엔드 Spring Boot 교체".

- [x] Task 1 — 스캐폴딩·헬스체크·SecurityConfig 초기판 (Boot 4.1.0·Jackson 3 확인)
- [x] Task 2 — 도메인 6종·Flyway V1(유니크 제약 이름 SQL 고정)·리포지토리·TRUNCATE 테스트 베이스
- [x] Task 3 — 토큰 필터·로그인·가입·DRF 호환 에러 핸들러·공통 비밀번호 500개
- [x] Task 4 — 방 CRUD(중복 400 고정 문자열·경합 안전망)·프로필 get-or-create
- [x] Task 5 — 푸시 기기 등록(토큰 계정 이전)·해제(항상 204)
- [x] Task 6 — 웹 푸시 발송: VAPID 공개키 EC 파생·@Async best-effort·만료 구독 정리
- [x] Task 7 — 낙상 API: 멱등 POST(중복 200·푸시 없음)·acknowledge·201에만 비동기 푸시
- [x] Task 8 — 통합 검증: 서버 36·웹 20·앱 4·E2E 2종 통과 (web-push AES128GCM fix 포함)
- [x] Task 9 — Django 제거·README Spring 기준 갱신
- [x] 최종 브랜치 전체 리뷰 + 문서 정리(정적 서버 명령·e2e README·RFC 주석·package-lock)

## 14. ALERTED 재무장 버그 수정 (2026-07-25)

전체 코드 점검에서 나온 확인된 버그 1건이다. `ALERTED` 상태에서 2초 이상 미검출된 뒤 여전히 바닥에 누운 채 재검출되면 상태가 `STANDING`으로 떨어져, 같은 낙상이 두 번 전송될 수 있었다. 경위는 context-notes.md "ALERTED 재무장 버그".

- [x] RED — `detector.test.js`에 재현 테스트 2개 추가(재검출 직후 상태 유지, 누운 채 뒤척임 시 중복 없음) → 실패 확인
- [x] GREEN — `detector.js` NO_PERSON 복귀 조건에 `ALERTED` 분기 추가 → 통과 확인
- [x] 검증 — 웹 22 / 서버 36 / 앱 4 전부 통과

## 15. 백엔드 구현 설명 문서 (2026-07-26)

Spring Boot 백엔드의 구현 구조와 동작을 설명하는 `docs/backend-architecture.html`을 만든다. Django 시절 같은 이름의 문서가 있었으나 백엔드 교체(13절) 때 삭제됐고 이것이 그 후속이다. 독자는 Spring 기본은 아는 백엔드 입문자로 잡아 어노테이션·DI 설명은 생략하고, 이 프로젝트가 내린 선택과 그 근거에 지면을 쓴다. 구성은 "요청 한 건의 여정 → 주제별 심화". 경위는 context-notes.md "백엔드 구현 설명 문서".

- [x] 1절 전체 지도 — 스택·패키지 트리·계층 다이어그램·엔티티 6종과 관계
- [x] 2절 요청의 여정 — `POST /api/falls/` 한 건을 필터→컨트롤러→서비스→DB→비동기 푸시까지 추적
- [x] 3절 인증 — 토큰 필터·permitAll 3개·STATELESS·BCrypt
- [x] 4절 소유권 격리 — `findByIdAndGuardianId` 패턴과 403이 아닌 404를 고른 이유
- [x] 5절 멱등성 — `uniq_fall_dedup`·트랜잭션 경계·201/200 분기와 푸시 조건
- [x] 6절 검증·에러 계약 — 2단 검증 구조·GlobalExceptionHandler 매핑
- [x] 7절 푸시 — VAPID 공개키 파생·@Async best-effort·AES128GCM 명시 이유
- [x] 8절 마이그레이션·테스트·실행
- [x] 검증 — 26개 인용 줄번호를 소스와 대조(전부 일치), 테스트 36개 재실행 확인, HTML 구조·앵커·상대링크 검증, macOS WebKit으로 렌더 확인 — 렌더 중 CSS 버그 1건 발견·수정

## 16. 발표자료 타겟 재정의·비즈니스 모델 추가 (2026-07-26)

`web/pre.html`을 13장 → 19장으로 확장했다. 핵심은 **타겟을 독거노인에서 부모부양세대(보호자)로 옮긴 것**이고, 그 근거·시장 규모·수익 모델·확장 전략을 슬라이드로 세웠다. 경위와 판단 근거는 context-notes.md "발표자료 타겟 재정의".

- [x] 사전과제 PDF·기존 13장 정독, 실제 코드와의 불일치 확인
- [x] 웹 조사 — 고령층 인터넷 이용률·노인 빈곤율·자녀 동거율·부양세대 인구·응급안전안심·요양시설·경쟁 단가
- [x] 근거 화면 캡쳐 5건(헤드리스 Chrome) → 헤드라인 영역 크롭 → JPEG 인라인 임베드
- [x] 5장 신설 — 최초 페르소나(독거노인)와 폐기하지 않은 이유, 그리고 두 개의 벽(인터넷 76.9%·빈곤율 39.7%)
- [x] 6장 신설 — 사용자/결제자 분리, "내가 나가 있는 동안" 핵심 질문, 자녀 동거율 20.1%→10.3%
- [x] 7장 신설 — TAM/SAM/SOM 깔때기, 40·50대 31.7%(약 1,630만 명)
- [x] 16장 신설 — B2C·B2G·B2B 3트랙
- [x] 17장 신설 — 방 개수별 첫 해 총비용 비교(우리만 평평한 선), 한계비용 0 근거
- [x] 18장 신설 — 제주 고독사 증가율 7.7배 근거·실증 조건·3단계 로드맵
- [x] 1·13·19장 갱신 — Django→Spring Boot, 폴링→웹 푸시 병기, 요약 5칸, 출처 8건 추가
- [x] 색 검증 — dataviz 팔레트 검증기로 blue/neutral 쌍 통과 확인(CVD ΔE 19.1), 4단계 파랑 램프는 탈락(ΔE 6.3)해 3단계 명도 단조 램프+직접 라벨로 대체
- [x] 렌더 검증 — 19장 전부 헤드리스 렌더 확인, 깔때기 텍스트 충돌·카드 상단 정렬 쏠림 2건 발견·수정
- [x] 검증 — 웹 22 통과, 서버 36 통과, 구조 검사(19장 순차·태그 균형·Django 잔재 0·placeholder 0)

## 17. Flutter 앱 Android 지원 (2026-07-27)

12절에서 걷어냈던 Android를 다시 붙였다. 이번엔 FCM 없이 로컬 알림만이다. 경위는 context-notes.md "Android 재지원".

- [x] 설계 — 화면 5개는 그대로, 갈라지는 곳은 알림·서버 주소 둘뿐. Flutter Web은 범위 밖(guardian.html과 중복)
- [x] `android/` 생성 — `flutter create --platforms=android --org com.example`, 커밋 19개 파일
- [x] `flutter create` 부작용 3개 되돌림 — `.metadata`의 ios 항목 복원, `pubspec.lock` 22.0.1 유지, 템플릿 `test/widget_test.dart` 삭제
- [x] 알림 — 채널 `fall_alerts`, `Importance.max`/`Priority.high`, Android 13+ 런타임 권한 요청. iOS 설정 불변
- [x] 알림 테스트 3종 — Android 초기화 설정 존재·헤드업 값·iOS 설정 불변(조용히 실패하는 자리라 값으로 고정)
- [x] 서버 주소 — `API_HOST` 우선순위 유지, 기본값만 Android면 `10.0.2.2`
- [x] 매니페스트 — 평문 HTTP 전역 허용, `POST_NOTIFICATIONS`·`INTERNET`, `tel` 가시성, 표시명 `Fall Guardian`
- [x] Gradle — `flutter_local_notifications` 22가 요구하는 core library desugaring 설정. 계획은 `android/`를 생성물로 두려 했지만 이게 없으면 APK 빌드가 시작조차 안 된다
- [x] 문서 — README 실행법·미검증 경고, 수동 검증 7절, 테스트 개수 4→7
- [x] 검증 — `flutter analyze` 무경고, `flutter test` 7개 통과
- [ ] **미검증** — APK 빌드·에뮬레이터 접속·알림 표시·권한 팝업·`tel` 발신. 이 맥에 Android SDK가 없다. 설치 후 `docs/manual-verification.md` 7절
## 18. 낙상 기록 삭제 (2026-07-27)

- [x] 설계 — 완전 삭제 채택(소프트 삭제 기각), 확인한 기록만, 웹·앱 공용 엔드포인트 1개
- [x] 서버 — `DELETE /api/falls/{id}/` 204/400/404, 소유권 판정이 확인 여부보다 먼저
- [x] 서버 테스트 3종 — 확인한 기록 204·목록에서 소멸 / 미확인 400·행 보존 / 남의 기록은 확인 여부 무관 404
- [x] 보호자 페이지 — 확인 상태에 따라 버튼 하나만(확인 또는 삭제), `confirm()` 경유
- [x] 앱 — 상세 화면 삭제 버튼(미확인이면 비활성), `showDialog` 경유, `pop(null)` → 목록 재조회
- [x] 앱 부수 개선 — 스와이프 백도 같은 null 경로를 타 목록이 즉시 갱신된다
- [x] 문서 — 엔드포인트 표, 수동 검증 8절, README 테스트 개수 36→39
- [x] 검증 — 서버 39 통과, 웹 회귀 통과, `flutter analyze` 무경고·앱 4 통과(알림 테스트 3개가 붙기 전이다)
