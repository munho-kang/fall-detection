# Flutter 웹 지원 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 fall_guardian Flutter 앱(Android/iOS)을 코드 재작성 없이 웹 브라우저에서도 동일하게 실행되게 한다.

**Architecture:** 별도 웹앱을 만들지 않고 `app/lib/` 전체를 웹으로 컴파일한다. 웹 컴파일을 막는 두 지점만 고친다 — `api.dart`의 `dart:io`를 `foundation.dart`(`kIsWeb`·`defaultTargetPlatform`) 기반 순수 함수로 교체하고, `notifications.dart`에 웹 가드를 넣는다. 그 다음 `flutter create --platforms=web .`으로 `app/web/`을 생성하고 index.html·manifest를 앱에 맞게 다듬는다.

**Tech Stack:** Flutter(웹 타깃, dart2js), 기존 의존성 그대로(http·shared_preferences·url_launcher·flutter_local_notifications). 백엔드(Spring Boot :8000)는 무수정 — CORS가 이미 전 오리진 허용.

**스펙:** `docs/superpowers/specs/2026-08-09-flutter-web-support-design.md`

## Global Constraints

- 새 의존성 추가 금지 — pubspec.yaml의 dependencies는 그대로다.
- 포트는 8000 고정, `--dart-define=API_HOST`가 항상 최우선(스펙 결정 2).
- 웹 폴더명은 Flutter 규약대로 소문자 `app/web/`이다.
- 사용자 노출 문구는 전부 한국어(기존 관례).
- 각 태스크 종료 시 `flutter analyze` 경고 0, `flutter test` 전체 통과.
- 커밋 메시지는 한국어 관례(`fix:`·`feat:`·`docs:` + 한 줄 요약)를 따르고 아래 푸터를 붙인다:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 모든 flutter 명령은 `app/`에서, gradle 명령은 `backend/`에서 실행한다.

---

### Task 1: api.dart — dart:io 제거, baseUrl을 테스트 가능한 순수 함수로

`dart:io`의 `Platform`은 웹(wasm)에서 컴파일이 안 되고 웹(JS)에선 런타임에 던진다.
분기를 전부 파라미터로 받는 `resolveBaseUrl`을 만들고 getter는 1줄 접착제로 남긴다.

**Files:**
- Modify: `app/lib/api.dart:3-34` (import와 baseUrl getter)
- Test: `app/test/api_test.dart` (그룹 추가)

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `Api.resolveBaseUrl({required String apiHostDefine, required bool isWeb, required Uri pageUri, required TargetPlatform platform}) → String` (@visibleForTesting), `Api.baseUrl`(기존 시그니처 유지 — 호출부 무수정)

- [ ] **Step 1: 실패 테스트 작성**

`app/test/api_test.dart` import 블록에 한 줄 추가 (`package:fall_guardian/models.dart` 다음, `package:flutter_test` 앞):

```dart
import 'package:flutter/foundation.dart' show TargetPlatform;
```

`main()` 끝(마지막 `testWidgets` 뒤)에 그룹 추가:

```dart
  // baseUrl 분기 — 웹 지원으로 dart:io Platform을 걷어내면서 분기가 전부 주입 가능해졌다
  group('resolveBaseUrl', () {
    test('API_HOST가 지정되면 플랫폼과 무관하게 그 호스트다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '192.168.0.5',
          isWeb: true,
          pageUri: Uri.parse('http://192.168.0.7:8080/'),
          platform: TargetPlatform.android,
        ),
        'http://192.168.0.5:8000',
      );
    });

    test('웹은 페이지를 연 호스트가 곧 API 호스트다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: true,
          pageUri: Uri.parse('http://192.168.0.7:8080/index.html'),
          platform: TargetPlatform.windows,
        ),
        'http://192.168.0.7:8000',
      );
    });

    test('웹인데 페이지 호스트가 비면(file:// 등) 127.0.0.1로 간다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: true,
          pageUri: Uri.parse('file:///C:/site/index.html'),
          platform: TargetPlatform.windows,
        ),
        'http://127.0.0.1:8000',
      );
    });

    test('Android 에뮬레이터에서 호스트는 10.0.2.2다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: false,
          pageUri: Uri(),
          platform: TargetPlatform.android,
        ),
        'http://10.0.2.2:8000',
      );
    });

    test('iOS 시뮬레이터·데스크톱은 127.0.0.1이다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: false,
          pageUri: Uri(),
          platform: TargetPlatform.iOS,
        ),
        'http://127.0.0.1:8000',
      );
    });
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/api_test.dart`
Expected: 컴파일 실패 — `The method 'resolveBaseUrl' isn't defined for the type 'Api'`

- [ ] **Step 3: 구현**

`app/lib/api.dart`의 import에서 `dart:io` 줄을 지우고 foundation을 추가한다.

기존(3-8행):
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
```

변경:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
```

기존 baseUrl getter(26-34행, 주석 포함)를 통째로 교체:

```dart
  // 우선순위: --dart-define=API_HOST(같은 와이파이의 서버 IP) > 플랫폼 기본값.
  // 웹은 페이지를 서빙한 호스트가 곧 백엔드가 있는 LAN 호스트다(호스트가 없는
  // file:// 실행은 127.0.0.1). iOS 시뮬레이터·데스크톱은 호스트를 127.0.0.1로 본다.
  // Android 에뮬레이터에서 127.0.0.1은 호스트가 아니라 에뮬레이터 자신이다. 호스트는 10.0.2.2다.
  static String get baseUrl => resolveBaseUrl(
        apiHostDefine: const String.fromEnvironment('API_HOST'),
        isWeb: kIsWeb,
        pageUri: Uri.base,
        platform: defaultTargetPlatform,
      );

  // 분기가 전부 파라미터라 VM 테스트에서 웹·Android 경로를 그대로 재현할 수 있다
  @visibleForTesting
  static String resolveBaseUrl({
    required String apiHostDefine,
    required bool isWeb,
    required Uri pageUri,
    required TargetPlatform platform,
  }) {
    if (apiHostDefine.isNotEmpty) return 'http://$apiHostDefine:8000';
    if (isWeb) {
      return pageUri.host.isEmpty
          ? 'http://127.0.0.1:8000'
          : 'http://${pageUri.host}:8000';
    }
    return platform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }
```

- [ ] **Step 4: 통과 확인**

Run: `cd app && flutter test`
Expected: 전체 통과 (기존 테스트 포함 — baseUrl 호출부는 시그니처가 안 변했다)

- [ ] **Step 5: analyze 확인**

Run: `cd app && flutter analyze`
Expected: No issues found

- [ ] **Step 6: 커밋**

```bash
git add app/lib/api.dart app/test/api_test.dart
git commit -m "feat: baseUrl에서 dart:io 제거 — 웹 컴파일 가능한 resolveBaseUrl로 분리"
```

---

### Task 2: notifications.dart — 웹에서는 OS 알림을 조용히 건너뛴다

`flutter_local_notifications`는 웹 구현이 없어 호출 시 `MissingPluginException`이 난다.
가드를 래퍼 안에 넣어 호출부 3곳(main.dart:15, main_shell.dart:50·57)은 무수정으로 둔다.
웹에서는 기존 사고 발생 모달이 알림 역할을 한다(스펙 결정 3).

**Files:**
- Modify: `app/lib/notifications.dart`
- Test: `app/test/notifications_test.dart` (테스트 추가)

**Interfaces:**
- Consumes: 없음 (Task 1과 독립)
- Produces: `Notifications.debugIsWebOverride` (`bool?`, @visibleForTesting — VM 테스트에서 웹 경로 재현용). `init()`/`show()` 시그니처는 기존 그대로.

- [ ] **Step 1: 실패 테스트 작성**

`app/test/notifications_test.dart`의 `main()` 끝에 추가:

```dart
  // 웹에는 플러그인 구현이 없다 — 가드가 없으면 아래 두 호출은
  // 플러그인 채널 호출까지 내려가 예외로 끝난다(테스트 환경에도 채널이 없다)
  test('웹에서는 init이 OS 알림 플러그인을 건드리지 않는다', () async {
    Notifications.debugIsWebOverride = true;
    addTearDown(() => Notifications.debugIsWebOverride = null);

    await Notifications.init();
  });

  test('웹에서는 show도 OS 알림 플러그인을 건드리지 않는다', () async {
    Notifications.debugIsWebOverride = true;
    addTearDown(() => Notifications.debugIsWebOverride = null);

    await Notifications.show(_event());
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/notifications_test.dart`
Expected: 컴파일 실패 — `The setter 'debugIsWebOverride' isn't defined for the type 'Notifications'`

- [ ] **Step 3: 구현**

`app/lib/notifications.dart` 3행 import 교체:

기존: `import 'package:flutter/foundation.dart' show visibleForTesting;`
변경: `import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;`

클래스 상단 `static final _plugin = ...` 다음에 추가:

```dart
  // 웹에는 이 플러그인의 구현이 없다(호출 시 MissingPluginException). 웹에서는 탭이
  // 열려 있는 동안 사고 발생 모달이 알림 역할을 하므로 OS 알림은 조용히 건너뛴다.
  // kIsWeb은 상수라 VM 테스트에서 웹 경로를 못 타 — 오버라이드를 열어 둔다.
  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get _isWeb => debugIsWebOverride ?? kIsWeb;
```

`init()` 첫 줄에 가드 추가:

```dart
  static Future<void> init() async {
    if (_isWeb) return;
    await _plugin.initialize(settings: settings);
```

`show()` 첫 줄에 가드 추가 (`isEnabled()`보다 앞 — 어차피 안 보낼 거면 저장소도 안 읽는다):

```dart
  static Future<void> show(FallEvent event) async {
    if (_isWeb) return;
    final on = await isEnabled();
```

- [ ] **Step 4: 통과 확인**

Run: `cd app && flutter test`
Expected: 전체 통과

- [ ] **Step 5: analyze 확인**

Run: `cd app && flutter analyze`
Expected: No issues found

- [ ] **Step 6: 커밋**

```bash
git add app/lib/notifications.dart app/test/notifications_test.dart
git commit -m "feat: 웹에서는 OS 알림을 건너뛴다 — 인앱 사고 모달이 알림 역할"
```

---

### Task 3: 웹 플랫폼 생성 — app/web/ + index.html·manifest 다듬기 + 빌드 검증

Task 1·2가 끝난 뒤 실행한다(웹 런타임에서 dart:io·플러그인 경로가 이미 안전해진 상태).

**Files:**
- Create: `app/web/index.html`, `app/web/manifest.json`, `app/web/favicon.png`, `app/web/icons/*` (flutter create가 생성)
- Modify: `app/web/index.html`, `app/web/manifest.json` (생성 직후 다듬기), `app/.metadata` (flutter create가 web 항목 추가)

**Interfaces:**
- Consumes: Task 1·2의 웹 안전한 api.dart·notifications.dart
- Produces: `flutter run -d chrome`·`flutter build web`이 도는 웹 플랫폼 (Task 4가 사용)

- [ ] **Step 1: 웹 플랫폼 생성**

Run: `cd app && flutter create --platforms=web .`
Expected: `web/` 생성 메시지. 이어서 `git status --short`로 확인 — 새 파일은 `app/web/` 아래뿐이고, 기존 파일 변경은 `app/.metadata`(web 마이그레이션 항목 추가)뿐이어야 한다. `lib/`·`pubspec.yaml`이 바뀌었으면 중단하고 diff를 확인한다.

- [ ] **Step 2: index.html 다듬기**

생성된 `app/web/index.html`에서 다음 항목을 교체한다(Flutter 버전에 따라 줄 위치가 다를 수 있으니 항목으로 찾는다. 나머지 보일러플레이트는 그대로 둔다):

| 항목 | 생성값 | 교체값 |
|---|---|---|
| `<html>` | `<html>` | `<html lang="ko">` |
| description meta | `content="A new Flutter project."` | `content="낙상 감지 보호자 알림"` |
| apple-mobile-web-app-title | `content="fall_guardian"` | `content="낙상 알림"` |
| `<title>` | `<title>fall_guardian</title>` | `<title>낙상 알림</title>` |
| theme-color | (없음) | `<title>` 윗줄에 `<meta name="theme-color" content="#00695C">` 추가 |

- [ ] **Step 3: manifest.json 교체**

`app/web/manifest.json`을 통째로 다음 내용으로 교체(아이콘 파일명은 flutter create 생성물 그대로):

```json
{
    "name": "낙상 알림",
    "short_name": "낙상 알림",
    "start_url": ".",
    "display": "standalone",
    "background_color": "#F4F6F6",
    "theme_color": "#00695C",
    "description": "낙상 감지 보호자 알림 앱",
    "orientation": "portrait-primary",
    "prefer_related_applications": false,
    "icons": [
        {
            "src": "icons/Icon-192.png",
            "sizes": "192x192",
            "type": "image/png"
        },
        {
            "src": "icons/Icon-512.png",
            "sizes": "512x512",
            "type": "image/png"
        },
        {
            "src": "icons/Icon-maskable-192.png",
            "sizes": "192x192",
            "type": "image/png",
            "purpose": "maskable"
        },
        {
            "src": "icons/Icon-maskable-512.png",
            "sizes": "512x512",
            "type": "image/png",
            "purpose": "maskable"
        }
    ]
}
```

색 근거: `#00695C`는 `app_theme.dart` 라이트 primary, `#F4F6F6`은 라이트 surface.

- [ ] **Step 4: 웹 빌드 확인**

Run: `cd app && flutter build web`
Expected: `√ Built build\web` (경고 없이 성공). 실패하면 에러의 파일·라이브러리를 확인한다 — dart:io 관련이면 Task 1이 미완이다.

- [ ] **Step 5: 회귀 확인**

Run: `cd app && flutter test && flutter analyze`
Expected: 전체 통과, No issues found

- [ ] **Step 6: 커밋**

```bash
git add app/web app/.metadata
git commit -m "feat: 웹 플랫폼 추가 — app/web 생성, 타이틀·manifest를 낙상 알림으로"
```

---

### Task 4: 실동작 검증 + README 웹 실행법

백엔드를 실제로 띄우고 크롬에서 전 화면을 돌려본다. 기동 절차가 막히면
`running-fall-guardian` 스킬을 참조한다(PostgreSQL `fall_detection` DB 필요).

**Files:**
- Modify: `README.md` (실행 섹션 84-89행 부근)

**Interfaces:**
- Consumes: Task 3의 웹 플랫폼
- Produces: 없음 (검증·문서 태스크)

- [ ] **Step 1: 백엔드 기동**

Run (Git Bash): `cd backend && ./gradlew bootRun` (PowerShell이면 `.\gradlew.bat bootRun`) — 백그라운드로 띄운다.
Expected: `Tomcat started on port 8000`

- [ ] **Step 2: 웹 앱 실행**

Run: `cd app && flutter run -d chrome` — 백그라운드로 띄운다.
Expected: 크롬 창이 열리고 스플래시 → 시작 화면. 콘솔에 예외 없음(특히 `MissingPluginException`·`Unsupported operation`이 뜨면 Task 1·2 누락 신호).

- [ ] **Step 3: 화면 순회**

회원가입 → 로그인 → 홈(빈 목록) → 방 관리에서 방 추가(예: 안방/1) → 설정에서 다크모드 토글 → 프로필 확인.
Expected: 전 화면이 Android와 동일하게 렌더링·동작. 새로고침(F5) 후에도 로그인 유지(localStorage 토큰).

- [ ] **Step 4: 낙상 이벤트 발생 → 인앱 모달 확인**

로그인 응답의 토큰을 복사해(브라우저 개발자도구 Application → Local Storage의 `flutter.fall_token` 값으로도 확인 가능) 낙상을 등록한다:

```bash
curl -s -X POST http://127.0.0.1:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username":"<가입한 아이디>","password":"<비밀번호>"}'
# 응답의 "token" 값을 아래 <TOKEN>에 넣는다

curl -s -X POST http://127.0.0.1:8000/api/falls/ \
  -H "Content-Type: application/json" -H "Authorization: Token <TOKEN>" \
  -d '{"room_name":"안방","room_number":1,"occurred_at":"2026-08-09T21:00:00+09:00","confidence":0.93}'
```

Expected: 5초 폴링 안에 웹 탭에 "사고 발생" 모달이 뜬다(OS 알림은 없음 — 의도된 동작). 확인을 누르면 닫히고 홈 미확인 목록에 남는다. 사고 상세 → 전화 걸기 버튼은 데스크톱에선 프로토콜 핸들러 창이 뜰 수 있다(알려진 제약, 스펙 3절).

- [ ] **Step 5: Android 회귀 스모크**

에뮬레이터가 있으면: `cd app && flutter run -d emulator-5554`로 로그인 → 홈까지 확인(10.0.2.2 기본값 회귀 — resolveBaseUrl 교체 부분).
에뮬레이터를 못 띄우는 환경이면: Task 1의 `resolveBaseUrl` Android 테스트 + 전체 테스트 통과를 회귀 근거로 기록하고 넘어간다.

- [ ] **Step 6: README에 웹 실행법 추가**

`README.md` 앱 실행 코드블록(84-86행 부근, `flutter run --dart-define=API_HOST=...` 줄 다음)에 한 줄 추가:

```
flutter run -d chrome                         # 웹(보호자 앱) — 크롬으로 실행
```

이어지는 설명 문단(89행 부근) 끝에 두 문장 추가:

```
웹은 페이지를 연 호스트가 곧 서버 주소다(크롬 실행은 localhost:8000, `API_HOST`로 바꿀 수 있다). 배포는 `cd app && flutter build web` — `app/build/web`의 정적 파일을 아무 정적 서버로 서빙하면 된다.
```

- [ ] **Step 7: 프로세스 정리 및 커밋**

띄워 둔 `flutter run`·`bootRun`을 종료한 뒤:

```bash
git add README.md
git commit -m "docs: 웹 실행·배포 방법 추가"
```
