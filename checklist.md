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
- [x] `api.dart` — 토큰 저장/헤더, `10.0.2.2:8000` 주의
- [x] `login.dart`
- [x] `fall_list.dart` — 방·시각·처리상태
- [x] `fall_detail.dart`
- [ ] 앱에서 DB의 이벤트가 보임 — 수동 검증 대기 (시뮬레이터 + 서버 구동 필요, task-13-report.md 참고)

## 6. 폴링 + 알림 + 동작

- [x] `poller.dart` — 5초 타이머, 최대 id 비교
- [x] 최초 로그인 시 알림 없이 id만 저장
- [x] `poller.dart` 새 id 판별 단위 테스트
- [x] `notifications.dart` — 로컬 알림
- [x] 3회 연속 폴링 실패 → "연결 끊김" 배너
- [x] 확인함 → `POST acknowledge`
- [x] 전화 (`tel:` 상수)
- [x] 신고 (더미 번호 + 이유 주석)
- [ ] 넘어지면 5초 내 에뮬레이터에 알림 확인 — 수동 검증 대기 (시뮬레이터 + 실제 알림, task-15-report.md 참고)

## 7. 마무리

- [x] 실제 웹캠으로 임계값 튜닝 (조정 내역은 context-notes.md에) — 4세션 실측(1~4차), CONFIG 7개 값 유지 확인 (context-notes.md "임계값 튜닝 기록")
- [x] 오탐지 없이 3회 연속 감지 성공 — 3차에서 낙상 4회 연속 감지·해당 구간 오탐지 없음. 단 배치 오탐지 여유는 미확정 (context-notes.md 4차·README 한계)
- [x] README — 실행 방법, 아키텍처, 사생활 보호 설명
- [x] README — 범위 밖 / 한계 명시 (설계 문서 12절)
