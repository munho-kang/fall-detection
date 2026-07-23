# 제품 완성도 라운드 — 푸시 알림·오프라인 큐·방/연락처 관리 설계

2026-07-23. 낙상 감지 파이프라인(감지→서버→앱)이 완성된 상태에서, README "알려진 한계" 중
실사용에 필요한 항목들을 해소하는 라운드다. 브레인스토밍 결정 기록이며 구현 계획의 입력이 된다.

## 1. 범위와 결정

이번 라운드에 포함한다.

1. **푸시 알림** — Android 앱은 FCM. iOS 앱은 유료 Apple Developer 계정이 없으므로 지금처럼 포그라운드 폴링 유지.
2. **보호자 웹 페이지 신설 + 표준 웹 푸시** — 낙상 목록·알림 구독·방/연락처 관리. iPhone은 홈 화면 추가(PWA)로 무료 백그라운드 알림을 얻는다(iOS 16.4+).
3. **오프라인 전송 큐** — 감지 페이지가 낙상 POST 3회 실패 후 포기하던 것을 localStorage 큐 적재 후 재전송으로 바꾼다.
4. **방·연락처 관리** — 고정 방 4개 choices와 앱의 전화번호 상수를 제거하고, 웹·앱 양쪽에서 CRUD.

범위 밖: 보호자 대시보드(방별 온라인 상태), iOS 앱 네이티브 푸시, FCM 웹(아래 결정), 다중 보호자.

### 푸시 아키텍처 결정 — 앱은 FCM, 웹은 표준 Web Push

- Android 백그라운드 푸시는 FCM 외에 실질적 대안이 없다. Firebase 프로젝트 1개는 필수.
- 웹은 FCM JS SDK 대신 **표준 Web Push API + VAPID**를 쓴다(`pywebpush`로 직접 발송).
  - 보호자 페이지에 Google SDK가 안 들어간다 — "영상은 기기를 벗어나지 않는다"는 프로젝트 정체성과 일관.
  - iOS Safari PWA 푸시는 표준 Web Push가 네이티브 메커니즘이라 가장 확실한 경로다.
  - 대가: Django 발송 경로가 2개(FCM HTTP v1, Web Push 프로토콜)가 된다. 둘 다 라이브러리가 처리하므로 감수한다.

## 2. 데이터 모델

새 모델 3개, 기존 수정 1개. 전부 `falls` 앱에 둔다(앱 분리는 이 규모에 과함).

```
Room            guardian FK · name(CharField 20) · number(PositiveSmallInt)
                unique (guardian, name, number)
GuardianProfile user OneToOne · elder_phone(CharField 20, blank 허용)
                "어르신께 전화" 번호의 서버 저장소. 접근 시 get_or_create.
PushDevice      guardian FK · kind("fcm"|"webpush") · token(TextField, unique) · created_at
                token은 FCM 등록 토큰 또는 Web Push 구독 JSON 문자열.
FallEvent       ROOM_CHOICES 제거(자유 문자열) +
                UniqueConstraint (guardian, room_name, room_number, occurred_at)
```

- FallEvent의 방 정보는 **문자열 스냅샷 유지**(Room FK 아님). 방을 삭제·개명해도 과거 기록이 안 깨진다.
- FallEvent의 새 unique 제약이 **오프라인 큐 멱등성의 근거**다. 재전송이 와도 중복 행이 생길 수 없다.
- 마이그레이션은 배포 Postgres에 그대로 적용 가능 — choices 제거는 제약 완화이고, unique 추가는 기존 시연 데이터에 동일 (guardian, room, number, occurred_at) 조합이 없는 한 통과한다.

## 3. API

기존 엔드포인트는 그대로. 추가분만 적는다. 인증·소유권 규칙은 기존과 동일(본인 것만 보인다).

```
GET/POST   /api/rooms/             POST body {name, number}
PATCH/DELETE /api/rooms/<id>/
GET/PUT    /api/profile/           {elder_phone}
POST       /api/push/devices/      {kind, token} — upsert. 토큰이 다른 계정에 등록돼 있으면
                                   현 사용자로 이전(같은 브라우저/기기에서 계정 전환 케이스).
DELETE     /api/push/devices/      body {token}. 로그아웃 시 해제.
GET        /api/push/vapid-key/    웹 푸시 공개키. 페이지에 하드코딩하지 않기 위한 조회용.
```

### POST /api/falls/ 확장 — 멱등 생성 + 푸시 발송

1. 동일 (guardian, room_name, room_number, occurred_at) 행이 있으면 기존 행을 **200**으로 반환. 푸시 없음.
2. 없으면 생성 후 **201**. 생성 경합으로 IntegrityError가 나면 재조회해 200 경로로.
3. 201일 때만 **데몬 스레드에서** 보호자의 모든 PushDevice로 발송한다.
   - 스레드인 이유: 감지 페이지의 POST 응답이 푸시 발송(외부 HTTP)을 기다리면 안 된다. Celery는 이 규모에 과하다.
   - 발송 실패는 로그만 남긴다. **어떤 실패도 201 응답에 영향을 주지 않는다** — 앱 폴링이 안전망이므로 푸시는 best-effort다.
   - 죽은 토큰은 그 자리에서 삭제한다: FCM `UnregisteredError`, Web Push 404/410.

### 푸시 발송 모듈 (`falls/push.py`)

- FCM: `firebase-admin`. notification+data 메시지 — notification부는 백그라운드에서 OS가 자동 표시("낙상 감지 / {room_name} {room_number}에서 낙상 감지"), data부는 `{type:"fall", id, room_name, room_number, occurred_at, confidence}`.
- Web Push: `pywebpush.webpush()` — data부와 같은 JSON 페이로드. 알림 표시는 서비스 워커 몫.
- 설정: 환경변수 `FIREBASE_SERVICE_ACCOUNT`(서비스 계정 JSON 문자열), `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`(mailto:주소). **미설정이면 해당 채널만 조용히 비활성** — 로컬 개발은 키 없이 나머지 전부 동작한다.
- requirements 추가: `firebase-admin`, `pywebpush`.

## 4. 감지 페이지 (web/)

### 오프라인 큐 — `js/queue.js` (신규, 순수 모듈)

- 브라우저 API 의존이 storage 주입뿐인 순수 모듈로 만들어 Vitest 대상에 넣는다. `enqueue(payload)`, `flush(postFn)`.
- localStorage 키 `fall_queue`, JSON 배열, FIFO.
- `postFall` 3회 실패 시: 포기 대신 큐 적재. 배너 문구 "전송 실패 — 저장해 두었다가 연결되면 다시 보냅니다".
- flush 시점: 페이지 로드, `online` 이벤트, 60초 주기, 새 낙상 전송 성공 직후.
- flush 규칙: 항목별로 201(신규)·200(중복) 모두 성공으로 보고 제거. 실패하면 순서 보존을 위해 중단하고 다음 기회에. 401은 기존 동작대로 로그아웃.

### 방 선택 연동

- `detect.html`의 고정 4개 `<select>`를 `GET /api/rooms/` 결과로 대체.
- 방이 없으면 그 자리에서 이름+번호를 입력해 바로 추가할 수 있다(인라인 POST /api/rooms/). 설치하는 사람이 카메라 기기 앞에서 방을 만들 수 있어야 설치 흐름이 안 끊긴다.

## 5. 보호자 웹 페이지 (신규)

- 파일: `web/guardian.html` + `web/js/guardian.js` + `web/sw.js` + `web/manifest.webmanifest` (+ 아이콘 192/512px). 기존 `js/api.js` 재사용.
- 구성: 낙상 목록(5초 폴링, 확인 버튼, 앱 fall_list와 동등) · 알림 켜기 버튼 · 방 관리(추가/삭제/이름 변경) · 어르신 연락처 수정 · 로그아웃.
- 알림 켜기 = `Notification.requestPermission` → `pushManager.subscribe`(공개키는 `/api/push/vapid-key/`) → 구독 JSON을 `/api/push/devices/`에 `{kind:"webpush"}`로 등록.
- `sw.js`는 바닐라 JS 소품이다 — `push` 이벤트에 `showNotification`, `notificationclick`에 guardian.html 포커스/열기.
- 로그인 연결: `index.html`에 "보호자 페이지" 링크. `guardian.html`은 토큰 없으면 `index.html?next=guardian.html`로 보내고, 로그인 성공 시 `next`를 존중한다(화이트리스트: guardian.html, detect.html — 오픈 리다이렉트 방지).
- iPhone: Safari에서 guardian.html → 공유 → 홈 화면에 추가 → 홈 화면 앱으로 열어 알림 켜기. iOS 16.4+ 필요. 절차를 배포 문서에 적는다.
- GitHub Pages 경로 주의: 사이트가 `/<repo>/web/`에 서빙되므로 SW 등록·manifest 경로는 전부 상대 경로로 쓴다(스코프 `web/`).

## 6. Flutter 앱

### FCM (Android 한정)

- `firebase_core` + `firebase_messaging` 추가. 초기화·토큰 등록·리스너는 전부 `Platform.isAndroid` 가드 안. iOS 코드 경로는 지금과 동일하다.
- 로그인 후 + `onTokenRefresh` 시 FCM 토큰을 `/api/push/devices/`에 등록, 로그아웃 시 DELETE.
- `google-services.json`은 커밋한다(클라이언트 설정값, 비밀 아님 — Firebase 표준 관행).
- Android 13+ 알림 권한은 firebase_messaging의 permission 요청으로 처리한다.

### 알림 중복 방지 규칙

Android의 낙상 알림은 FCM이 전담한다 — 백그라운드는 OS 자동 표시, 포그라운드는 `onMessage`에서 기존 `notifications.dart`로 로컬 알림(id=이벤트 id). **폴링은 Android에서 목록 갱신만 하고 알림을 울리지 않는다.** iOS는 지금처럼 폴링이 알림을 울린다. 알림 발생원이 플랫폼당 정확히 하나가 되어 중복이 구조적으로 불가능하다.

### 관리 화면

- 목록 화면 앱바에 설정(⚙) → 설정 화면: 방 목록·추가·삭제·이름 변경 + 어르신 전화번호 편집(GET/PUT /api/profile/).
- `fall_detail.dart`의 `_elderPhone` 상수 제거 → 프로필 값 사용. 미설정이면 "어르신께 전화" 버튼 비활성 + 설정 안내. `_emergencyPhone`(119 더미)은 그대로 둔다.
- `models.dart`에 Room·Profile, `api.dart`에 rooms/profile/devices 메서드 추가.

## 7. 오류 처리 요약

- 푸시 발송 실패 → 로그만, 응답 불변, 폴링이 안전망.
- 죽은 푸시 토큰 → 발송 시점에 삭제.
- 큐 flush 중 실패 → 중단 후 다음 트리거에서 재개. 순서 보존.
- 큐 재전송 중복 → 서버 unique 제약 + 200 응답으로 흡수.
- 방 0개인 감지 페이지 → 인라인 추가 UI.
- elder_phone 미설정 → 통화 버튼 비활성 + 안내.
- VAPID/Firebase 키 미설정 → 해당 채널만 비활성, 나머지 기능 정상.

## 8. 테스트

- **pytest** (기존 10 + 약 12): 방 CRUD·소유권 격리, 프로필 get/put, 기기 등록 upsert(계정 이전 포함), 낙상 중복 POST → 200·행 불변, 201 시 푸시 호출(mock)·실패해도 201, 죽은 토큰 삭제.
- **Vitest** (기존 10 + 약 5): queue.js — 3회 실패 후 적재, flush 성공/중복 제거, 실패 시 중단·순서 보존, storage 라운드트립.
- **Flutter** (기존 4 + 1~2): "Android는 폴링 알림 없음" 분기.
- 수동 검증: Android 실기기/에뮬레이터 백그라운드 FCM 수신, 데스크톱 브라우저 웹 푸시, iPhone 홈 화면 PWA 푸시, 감지 페이지 오프라인→온라인 큐 재전송.

## 9. 배포·문서

- Render 환경변수 3개 추가: `FIREBASE_SERVICE_ACCOUNT`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`.
- `docs/DEPLOYMENT.md`에 추가: Firebase 프로젝트 생성→Android 앱 등록→google-services.json 배치, VAPID 키 생성 명령, 환경변수 입력, iPhone 홈 화면 추가 절차.
- README 갱신: "알려진 한계"에서 해소된 항목(백그라운드 알림·전송 유실·방/연락처 고정) 정리, 구조도에 푸시 경로 추가.
