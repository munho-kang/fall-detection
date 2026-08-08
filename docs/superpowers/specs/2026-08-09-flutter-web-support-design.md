# Flutter 웹 지원 설계

2026-08-09. 이미 Android/iOS로 돌아가는 fall_guardian 앱을 웹 브라우저에서도 똑같이 쓸 수
있게 한다. 브레인스토밍 결정 기록이다.

## 1. 배경

앱은 Flutter 하나로 짜여 있고(`app/lib/`, 화면 12개), 보호자는 지금 폰에서만 낙상 알림을
확인할 수 있다. 데스크톱 브라우저에서도 같은 화면을 열 수 있으면 폰이 없는 자리(사무실 PC 등)
에서도 낙상 확인이 된다.

탐색 결과 웹 컴파일을 막는 지점은 전체 코드에서 딱 두 곳이다.

1. `api.dart:5` — `dart:io`의 `Platform`으로 Android 에뮬레이터 여부를 가른다. `dart:io`는
   웹 타깃에서 쓸 수 없다.
2. `notifications.dart` — `flutter_local_notifications`의 웹 경로는 쓰지 않기로 했다.
   웹 알림은 결정 3에 따라 인앱 모달 전용이다.

나머지 의존성은 전부 웹 구현이 있다: `http`(fetch), `shared_preferences`(localStorage),
`url_launcher`(새 탭/프로토콜 핸들러). 백엔드 CORS는 이미 전 오리진·전 메서드·전 헤더
허용이고(`CorsConfig.java` — 토큰 헤더 인증이라 credentials 불요) 백엔드 수정은 없다.

루트의 `web/` 폴더(MediaPipe 감지 페이지)와는 별개다 — 그쪽은 낙상을 "감지하는" 카메라
페이지고, 이번 작업은 보호자가 쓰는 "앱 화면"을 웹으로 여는 것이다.

## 2. 범위와 결정

1. **별도 웹앱을 새로 짜지 않고 기존 Flutter 코드를 웹으로 컴파일한다**(사용자 결정).
   `flutter create --platforms=web .`으로 `app/web/`(index.html·manifest·아이콘)을 생성하면
   (`.metadata`에 web 항목이 추가되는 것 외에 기존 파일은 건드리지 않는다) 화면 12개와
   폴링·테마·로컬 저장 로직이 그대로 돈다. 앱을 고치면 웹도 자동으로 같이
   고쳐진다. HTML/JS로 12개 화면을 재구현하는 안(로직 이중 관리)과 루트 `web/`에 보호자
   화면을 덧붙이는 안(요청된 `app/` 안 구조와 다르고 역시 재구현)은 제외했다.
   폴더명은 Flutter 플랫폼 규약대로 소문자 `web/`이다(`android/`·`ios/`와 나란히).

2. **웹 baseUrl 기본값은 "페이지를 연 호스트:8000"**(사용자 결정). 우선순위는 기존 그대로
   `--dart-define=API_HOST` > 플랫폼 기본값이고, 웹 분기만 추가한다:
   `kIsWeb`이면 `Uri.base.host`(페이지를 서빙한 호스트가 곧 백엔드가 있는 LAN 호스트,
   비어 있으면 127.0.0.1), 아니면 기존처럼 Android 10.0.2.2 / 그 외 127.0.0.1.
   `dart:io`는 완전히 제거하고 `foundation.dart`의 `kIsWeb`·`defaultTargetPlatform`으로
   바꾼다 — dart2js·wasm 어느 쪽에서도 컴파일된다.

3. **웹 알림은 인앱 다이얼로그만 쓴다**(사용자 결정). `Notifications.init()`/`show()` 진입부에
   `kIsWeb`이면 조용히 반환하는 가드를 래퍼 안에 넣는다 — 호출부 3곳(main.dart,
   main_shell.dart×2)은 무수정. 탭이 열려 있는 동안은 기존 사고 발생 모달이 알림 역할을
   한다. 브라우저 Notification API 연동(JS interop)은 제외했다 — 탭을 닫으면 어차피 폴링이
   멈춰 실익이 작고, 필요해지면 별도 라운드로 한다.

4. **index.html·manifest를 앱에 맞게 다듬는다** — 타이틀 "낙상 알림", `lang="ko"`,
   테마색 `#00695C`(app_theme 라이트 팔레트 primary).

## 3. 알려진 웹 제약 (수용)

- OS 푸시알림 없음 — 탭이 열려 있을 때만 인앱 모달로 알린다.
- 사고 상세의 전화 걸기(`tel:`)는 데스크톱 브라우저에서 OS 프로토콜 핸들러 선택창이 뜬다.
  모바일 브라우저에서는 정상 동작한다.
- 토큰은 localStorage에 저장된다(shared_preferences 웹 구현) — 브라우저별로 따로 로그인한다.

## 4. 검증

- `flutter analyze` 경고 0 유지, 기존 테스트 전체 통과(`flutter test`).
- `flutter build web` 성공.
- 백엔드 기동 후 `flutter run -d chrome`으로 실동작 확인: 로그인 → 홈 → 사고 목록/상세 →
  방 관리 → 설정(다크모드 전환) → 로그아웃, 그리고 낙상 이벤트를 만들어(감지 페이지 또는
  API 직접 호출) 웹 탭에 사고 모달이 뜨는지까지.
- Android 회귀 확인: 에뮬레이터에서 기존 흐름 그대로 도는지(특히 baseUrl 분기 교체 후
  10.0.2.2 기본값 유지).
