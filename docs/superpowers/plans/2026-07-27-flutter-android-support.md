# Flutter 앱 Android 지원 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS만 구성돼 있던 `app/`에 Android 플랫폼을 추가한다. 화면 코드는 한 줄도 고치지 않고, 플랫폼이 갈라지는 알림·서버 주소 두 곳만 손댄다.

**Architecture:** `flutter create --platforms=android`로 `android/` 폴더를 만들고, `lib/notifications.dart`에 Android 알림 경로를, `lib/api.dart`에 에뮬레이터 호스트(`10.0.2.2`) 분기를 더한다. 매니페스트에 평문 HTTP·알림 권한·인터넷 권한·`tel` 가시성 네 항목을 넣는다. `lib/` 나머지 8개 파일과 `ios/`는 건드리지 않는다.

**Tech Stack:** Flutter 3.44.0 / Dart, `flutter_local_notifications` 22.0.1, `url_launcher` 6.3.2, Gradle Kotlin DSL(AGP 템플릿 기본값).

설계 근거는 `docs/superpowers/specs/2026-07-27-flutter-android-support-design.md`에 있다. 판단이 갈리면 그 문서가 기준이다.

## Global Constraints

- **한국어** — 사용자에게 보이는 문구와 새로 쓰는 주석은 전부 한국어다. 한국어 문장은 마침표로 끝낸다(뒤에 목록이 와도 콜론으로 끝내지 않는다).
- **재사용이 이 작업의 요점이다** — `lib/` 10개 파일 중 바뀌어도 되는 것은 `notifications.dart`와 `api.dart` **둘뿐**이다. 화면 5개·`models.dart`·`poller.dart`·`main.dart`와 `ios/` 전체는 한 줄도 바뀌면 안 된다. 바뀌었으면 되돌린다. 화면을 고쳐야 하는 상황이 오면 설계가 틀린 것이니 멈추고 보고한다.
- **버전을 올리지 않는다** — `flutter create`가 `pub get`을 돌리면서 `pubspec.lock`을 `flutter_local_notifications` 22.0.1 → 22.2.0으로 올린다. 설계의 API 확인은 22.0.1 소스로 했으므로 lock을 되돌린다. `pubspec.yaml`은 어떤 경우에도 바뀌지 않는다.
- **고정 값** — 아래 문자열을 그대로 쓴다. 다르게 지으면 안 된다.
  | 항목 | 값 |
  |---|---|
  | `--org` | `com.example` |
  | `applicationId` / `namespace` | `com.example.fall_guardian` |
  | `android:label` | `Fall Guardian` |
  | 알림 채널 id | `fall_alerts` |
  | 알림 채널 이름 | `낙상 알림` |
  | 기본 아이콘 | `@mipmap/ic_launcher` |
- **Android SDK가 이 맥에 없다** — `flutter build apk`도, 에뮬레이터 실행도 **불가능하다.** 되는 검증은 `flutter analyze`와 `flutter test` 둘뿐이다. 빌드를 시도해 실패했다고 계획을 바꾸지 말고, 완료 보고에 **"APK 빌드와 실기기/에뮬레이터 동작은 미검증"**을 반드시 명시한다. 사용자가 이 상태를 알고 선택했다.
- **새 소스 파일 헤더** — 이번에 손으로 만드는 새 소스 파일은 `app/test/notifications_test.dart` 하나다. 첫 줄에 역할을 적은 한국어 주석을 넣는다. `android/` 아래 생성물은 Flutter 템플릿이므로 이 규칙 대상이 아니다(주석을 넣지 않는다).
- **수술적 변경** — 내 변경이 틀리게 만든 주석·문서 문장만 고친다. 그 외 인접 코드는 손대지 않는다.
- **2026-07-24 결정을 지운 것이 아니다** — 이 저장소에는 `checklist.md` 12절·`context-notes.md`에 "Android 지원 제거(2026-07-24)" 기록이 있다. 그 절들을 **수정하거나 삭제하지 않는다.** 이번 라운드는 그 뒤에 새 절로 덧붙여 "왜 다시 붙였고 무엇은 되살리지 않았는지"를 남긴다.
- **커밋** — 태스크당 1커밋. 한국어 semantic commit 메시지에 아래 트레일러를 붙인다.
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  ```

**사전 조건.** 작업 트리가 깨끗해야 태스크 1의 `git status` 검사가 의미를 가진다. 저장소 루트에서 확인한다.

```bash
git status --short
```

추적되지 않은 PDF 한 개(`[제주 지역대학 연합 창업 캠프] …pdf`)는 이 작업과 무관하니 그대로 둔다. `app/` 아래에 변경이 있으면 먼저 정리하고 시작한다.

---

## File Structure

| 파일 | 역할 | 태스크 |
|---|---|---|
| `app/android/**` (19개 파일) | Flutter Android 플랫폼 템플릿. 생성물이며 매니페스트 외에는 손대지 않는다. | 1 |
| `app/.metadata` | 추적 플랫폼 목록. `ios` 옆에 `android`가 **더해져야** 한다(대체가 아니다). | 1 |
| `app/pubspec.lock` | 의존성 잠금. 이번 작업으로 바뀌면 안 된다. | 1 |
| `app/lib/notifications.dart` | 알림 초기화·표시. Android 설정과 13+ 런타임 권한 요청을 더한다. | 2 |
| `app/test/notifications_test.dart` | **신규.** 두 플랫폼 설정이 다 채워져 있는지 고정한다. | 2 |
| `app/lib/api.dart` | `baseUrl` 게터에만 Android 분기를 더한다. 나머지 메서드는 건드리지 않는다. | 3 |
| `app/android/app/src/main/AndroidManifest.xml` | 평문 HTTP·알림 권한·인터넷 권한·`tel` 가시성·앱 표시명. | 4 |
| `README.md` | 실행법·다이어그램·테스트 개수·알려진 한계. | 5 |
| `docs/manual-verification.md` | Android SDK 설치 후 밟을 절차. | 5 |
| `checklist.md`, `context-notes.md` | 라운드 기록과 결정 근거. | 5 |

태스크 1이 폴더를 만들고 4가 그 안의 매니페스트를 고치므로 **4는 1에 의존한다.** 2와 3은 `lib/`만 건드려 1과 무관하고 서로도 독립이지만, 설계가 정한 순서(폴더 → 알림 → 주소 → 매니페스트 → 문서)를 그대로 따른다.

---

## Task 1: `android/` 폴더 생성

**Files:**
- Create: `app/android/**` (Flutter가 생성. 커밋되는 것은 19개 파일)
- Modify: `app/.metadata`
- Verify-unchanged: `app/pubspec.lock`, `app/pubspec.yaml`, `app/lib/**`, `app/ios/**`, `app/test/poller_test.dart`

**Interfaces:**
- Consumes: 없음(이 태스크가 첫 번째다).
- Produces: 태스크 4가 고칠 `app/android/app/src/main/AndroidManifest.xml`. 생성 직후 이 파일은 `android:label="fall_guardian"`이고 `<queries>` 블록에 `PROCESS_TEXT` 인텐트 하나만 들어 있다. Android 패키지는 `com.example.fall_guardian`이다.

**이 태스크에 새 테스트는 없다.** 폴더 생성이라 단위 테스트를 붙일 대상이 없다. 대신 **"무엇이 바뀌었는가"를 git으로 검사**하는 것이 이 태스크의 테스트다(Step 3). 회귀는 기존 4개 테스트로 본다.

- [ ] **Step 1: `flutter create`로 Android 플랫폼을 더한다**

```bash
cd app && flutter create --platforms=android --org com.example .
```

iOS 번들 ID가 `com.example.fallGuardian`이라 org는 `com.example`을 유지한다. Android 쪽은 snake_case 관례라 `com.example.fall_guardian`이 되는데, 두 플랫폼의 애플리케이션 ID는 서로 독립이라 철자가 달라도 문제가 없다.

프로젝트 이름은 넘기지 않는다. `flutter create`가 기존 `pubspec.yaml`의 `name: fall_guardian`을 읽어 쓴다(실측 확인 — 디렉터리 이름 `app`이 쓰이지 않는다).

**Android SDK가 없어도 이 명령은 성공한다.** 템플릿 파일을 쓰는 일이라 SDK를 보지 않는다. `Wrote 30 files.` 와 `All done!`이 나오면 된 것이다.

- [ ] **Step 2: `flutter create`가 흘린 템플릿 테스트를 지운다**

`flutter create`는 `test/widget_test.dart`(카운터 앱 예제)를 같이 만든다. 이 파일은 존재하지 않는 `MyApp`을 참조해서 **`flutter test` 전체를 컴파일 에러로 죽인다.**

```bash
rm app/test/widget_test.dart
```

- [ ] **Step 3: 무엇이 바뀌었는지 git으로 검사한다**

저장소 루트에서 본다.

```bash
git status --short app/
```

기대하는 출력은 정확히 이 세 줄이다.

```
 M app/.metadata
 M app/pubspec.lock
?? app/android/
```

- `app/lib/`·`app/ios/`·`app/pubspec.yaml`·`app/.gitignore`·`app/analysis_options.yaml`·`app/README.md`가 **한 줄이라도 나오면 안 된다.** 나오면 `git checkout -- <그 경로>`로 되돌린다.
- `app/.idea/`는 `flutter create`가 만들지만 `app/.gitignore`의 `.idea/`가 잡아서 출력에 안 나온다. 지울 필요 없다.
- `android/` 안의 `local.properties`·`gradlew`·`gradle-wrapper.jar`·`GeneratedPluginRegistrant.java`·`*.iml`은 `android/.gitignore`와 루트 `.gitignore`가 잡는다. 커밋 대상은 19개 파일이다.

- [ ] **Step 4: `.metadata`에서 사라진 `ios`를 되살린다**

`flutter create --platforms=android`는 `migration.platforms` 목록의 `ios` 항목을 **대체해 버린다**(실측 확인). 그대로 두면 이 프로젝트가 iOS를 추적하지 않게 된다.

`app/.metadata`의 이 부분을

```yaml
    - platform: android
      create_revision: 559ffa3f75e7402d65a8def9c28389a9b2e6fe42
      base_revision: 559ffa3f75e7402d65a8def9c28389a9b2e6fe42
```

이렇게 바꾼다. `ios`를 다시 붙이는 것이고, revision 값은 세 항목이 전부 같다.

```yaml
    - platform: android
      create_revision: 559ffa3f75e7402d65a8def9c28389a9b2e6fe42
      base_revision: 559ffa3f75e7402d65a8def9c28389a9b2e6fe42
    - platform: ios
      create_revision: 559ffa3f75e7402d65a8def9c28389a9b2e6fe42
      base_revision: 559ffa3f75e7402d65a8def9c28389a9b2e6fe42
```

바꾼 뒤 `root`·`android`·`ios` 세 항목이 다 있는지 확인한다.

```bash
grep -c "platform:" app/.metadata     # 3이 나와야 한다
```

- [ ] **Step 5: `pubspec.lock`을 되돌린다**

`flutter create`가 부른 `pub get`이 `flutter_local_notifications`를 22.0.1 → 22.2.0으로, `flutter_local_notifications_platform_interface`를 12.0.0 → 12.1.0으로 올린다. 설계의 API 확인은 22.0.1 소스로 했으니 되돌린다.

```bash
git checkout -- app/pubspec.lock
cd app && flutter pub get
grep -n 'version: "22' app/pubspec.lock     # 22.0.1이 나와야 한다
```

`flutter pub get`은 기존 lock을 존중하므로 다시 올라가지 않는다. `7 packages have newer versions incompatible with dependency constraints.` 는 정상 출력이니 무시한다.

이제 `git status --short app/`에 `app/pubspec.lock`이 없어야 한다.

- [ ] **Step 6: 정적 검사와 회귀 테스트를 돌린다**

```bash
cd app && flutter analyze && flutter test
```

기대: `No issues found!`, 그리고 **4개 PASS**(`poller_test.dart`). 아직 알림 테스트를 쓰기 전이라 4개다. 5개 이상 나오면 Step 2의 `widget_test.dart` 삭제가 안 된 것이다.

- [ ] **Step 7: 커밋**

```bash
git add app/android app/.metadata
git commit -F - <<'EOF'
feat: Flutter 앱에 Android 플랫폼 추가 — flutter create 생성물

flutter create --platforms=android --org com.example 으로 android/를 만들었다.
lib/·ios/·pubspec.yaml은 건드리지 않았다.

두 가지를 손으로 되돌렸다. flutter create가 .metadata의 ios 항목을 android로
대체해서 다시 붙였고, 같이 돌아간 pub get이 flutter_local_notifications를
22.2.0으로 올려서 검증된 22.0.1로 되돌렸다. 템플릿 test/widget_test.dart는
없는 MyApp을 참조해 테스트 전체를 죽이므로 삭제했다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 2: 알림 — Android 경로 추가

설계가 이 작업의 **핵심**으로 지목한 자리다. 지금 `InitializationSettings`에 `android` 필드가 없어서, Android에서 알림이 **예외도 로그도 없이 그냥 안 뜬다.** 낙상 감지 앱에서 알림이 안 뜨면 앱이 하는 일이 없다. 조용히 실패하는 종류라 테스트로 고정한다.

**Files:**
- Modify: `app/lib/notifications.dart`
- Create: `app/test/notifications_test.dart`

**Interfaces:**
- Consumes: `package:flutter_local_notifications/flutter_local_notifications.dart` 22.0.1. 확인한 시그니처는 아래와 같다(pub 캐시 소스 직접 확인).
  - `AndroidInitializationSettings(String defaultIcon)` — 위치 인자 1개
  - `AndroidNotificationDetails(String channelId, String channelName, {Importance importance, Priority priority, …})` — 앞 둘은 위치 인자
  - `FlutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<T>() → T?`
  - `AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission() → Future<bool?>`
- Produces:
  - `Notifications.settings` — `static const InitializationSettings`, `@visibleForTesting`. 지금까지 `initialize()` 호출 안에 인라인으로 있던 값을 밖으로 뺀 것이다.
  - `Notifications.details` — `static const NotificationDetails`, `@visibleForTesting`. 기존 `_details`의 새 이름이다.
  - `Notifications.init()`·`Notifications.show(FallEvent)` — 시그니처 그대로. `main.dart`와 `poller.dart`가 쓰는 이름이라 바뀌면 안 된다.

**왜 private을 풀었나.** 설계의 결정 2가 말하는 실패 모드는 "`android` 필드가 null이면 조용히 안 뜬다"이다. `flutter analyze`는 이걸 못 잡고, Android SDK가 없어 실기기 검증도 못 한다. 값이 채워져 있는지 보는 순수 단위 테스트가 이 자리에서 유일하게 가능한 검증이라 `_details`의 밑줄을 떼고 `settings`도 상수로 꺼냈다. `@visibleForTesting`이 "테스트 때문에 공개했다"는 사실을 코드에 남긴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/notifications_test.dart`를 새로 만든다.

```dart
// 알림 설정이 두 플랫폼 모두 채워져 있는지 — 비면 그 플랫폼에서 조용히 안 뜬다

import 'package:fall_guardian/notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 초기화 설정이 채워져 있다', () {
    expect(Notifications.settings.android, isNotNull);
    expect(Notifications.settings.android!.defaultIcon, '@mipmap/ic_launcher');
  });

  test('Android 알림은 헤드업으로 뜬다', () {
    final android = Notifications.details.android;

    expect(android, isNotNull);
    expect(android!.channelId, 'fall_alerts');
    expect(android.importance, Importance.max);
    expect(android.priority, Priority.high);
  });

  test('iOS 설정은 그대로다', () {
    expect(Notifications.settings.iOS, isNotNull);
    expect(Notifications.details.iOS, isNotNull);
  });
}
```

세 번째 테스트가 설계의 "**iOS 설정은 그대로 둔다**"를 고정한다. Android를 붙이다 iOS 쪽을 흘리면 여기서 걸린다.

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd app && flutter test test/notifications_test.dart
```

기대: **컴파일 에러로 실패**한다. `Notifications.settings`와 `Notifications.details`가 아직 없다(`Member not found: 'Notifications.settings'` 꼴의 메시지). 개별 테스트 실패가 아니라 로딩 실패로 나오는 것이 정상이다.

- [ ] **Step 3: `notifications.dart`를 고친다**

파일 전체를 아래로 바꾼다. `init()`과 `show()`의 시그니처, iOS 설정 값, `show()`의 제목·본문 문자열은 기존 그대로다.

```dart
// flutter_local_notifications 래퍼

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();

  // android/iOS 어느 쪽이든 null이면 그 플랫폼에서 예외도 로그도 없이 알림이 안 뜬다.
  // 조용히 실패하는 자리라 테스트가 붙잡는다.
  @visibleForTesting
  static const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    ),
  );

  @visibleForTesting
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'fall_alerts',
      '낙상 알림',
      // 낙상은 헤드업으로 즉시 떠야 한다. 기본 중요도면 배너 없이 상태바에만 쌓인다.
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  static Future<void> init() async {
    await _plugin.initialize(settings: settings);
    // Android 13+는 런타임 권한이 따로 있다. 매니페스트 선언만으로는 알림이 안 뜬다.
    // iOS 권한은 위 DarwinInitializationSettings가 initialize 중에 요청한다.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show(FallEvent event) async {
    final t = event.occurredAt;
    await _plugin.show(
      id: event.id,
      title: '${event.roomLabel}에서 낙상 감지',
      body: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} 발생 · 확인이 필요합니다',
      notificationDetails: details,
    );
  }
}
```

`resolvePlatformSpecificImplementation`은 iOS에서 `null`을 돌려주고 `?.`가 거기서 멈춘다. iOS 동작은 그대로다.

- [ ] **Step 4: 테스트를 돌려 통과를 확인한다**

```bash
cd app && flutter test
```

기대: **7개 PASS**(기존 poller 4 + 신규 3). 개수가 다르면 멈추고 원인을 본다.

- [ ] **Step 5: 정적 검사를 돌린다**

```bash
cd app && flutter analyze
```

기대: `No issues found!`. `@visibleForTesting` 멤버를 같은 라이브러리 안에서 쓰는 것은 경고 대상이 아니다(실측 확인).

- [ ] **Step 6: 커밋**

```bash
git add app/lib/notifications.dart app/test/notifications_test.dart
git commit -F - <<'EOF'
feat: Android 알림 경로 추가 — 채널 fall_alerts, 헤드업, 13+ 런타임 권한

InitializationSettings에 android 필드가 없으면 안드로이드에서 예외도 로그도
없이 알림이 그냥 안 뜬다. 낙상 앱에서 알림이 안 뜨면 앱이 하는 일이 없다.

analyze도 못 잡고 Android SDK가 없어 실기기 검증도 못 하는 자리라, 설정이
채워져 있는지 보는 단위 테스트 3개로 고정했다. 그래서 _details의 밑줄을 떼고
settings를 상수로 꺼냈다(@visibleForTesting). iOS 설정 값은 그대로다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 3: 서버 주소 — Android 에뮬레이터 분기

에뮬레이터 안에서 `127.0.0.1`은 호스트 맥이 아니라 **에뮬레이터 자신**을 가리킨다. 그대로 두면 서버에 영영 닿지 않는다. 안드로이드 에뮬레이터는 호스트를 `10.0.2.2`로 본다.

**Files:**
- Modify: `app/lib/api.dart:3-22` (import 블록과 `baseUrl` 게터. 나머지 메서드는 손대지 않는다)

**Interfaces:**
- Consumes: `dart:io`의 `Platform.isAndroid`.
- Produces: `Api.baseUrl` — `static String` 게터. 시그니처는 그대로다. 우선순위는 `API_HOST` → (Android면 `http://10.0.2.2:8000`, 아니면 `http://127.0.0.1:8000`).

**이 태스크에 새 테스트는 없다.** 테스트는 호스트 맥의 Dart VM에서 도니 `Platform.isAndroid`가 항상 false라, Android 분기를 밟을 방법이 없다. false 쪽만 확인하는 테스트는 기존 동작을 다시 쓰는 것뿐이라 값이 없다. 검증은 `flutter analyze`와 태스크 5의 수동 절차로 한다.

**대가를 알고 넘어간다.** `dart:io` 임포트가 생겨 `api.dart`는 이후 **웹 빌드가 불가능해진다.** 지금은 Android 전용으로 정했으니 맞는 선택이고, 나중에 웹을 붙이면 조건부 임포트(`dart:io`/`dart:html`)로 갈라야 한다. 설계 결정 3에 기록돼 있다.

- [ ] **Step 1: `dart:io` 임포트를 더한다**

`app/lib/api.dart`의 import 블록이다. 바꾸기 전.

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
```

바꾼 뒤. `dart:` 임포트끼리 알파벳 순서라 `convert` 다음이 `io`다. `show Platform`으로 들어오는 이름을 하나로 좁힌다.

```dart
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
```

- [ ] **Step 2: `baseUrl` 게터를 바꾼다**

주석까지 통째로 바꾼다. 바꾸기 전.

```dart
  // 우선순위: --dart-define=API_HOST(같은 와이파이의 Mac IP) > 시뮬레이터 기본값.
  // iOS 시뮬레이터·데스크톱은 호스트를 127.0.0.1로 본다.
  // 실기기는 같은 LAN의 Mac IP가 필요하므로 API_HOST로 지정한다.
  static String get baseUrl {
    const host = String.fromEnvironment('API_HOST');
    if (host.isNotEmpty) return 'http://$host:8000';
    return 'http://127.0.0.1:8000';
  }
```

바꾼 뒤. `API_HOST`가 이기는 기존 규칙은 그대로다 — 실기기 경로가 여기에 걸려 있다. 없을 때의 기본값만 갈린다.

```dart
  // 우선순위: --dart-define=API_HOST(같은 와이파이의 Mac IP) > 에뮬레이터/시뮬레이터 기본값.
  // iOS 시뮬레이터·데스크톱은 호스트를 127.0.0.1로 본다.
  // Android 에뮬레이터에서 127.0.0.1은 호스트가 아니라 에뮬레이터 자신이다. 호스트는 10.0.2.2다.
  // 실기기는 양쪽 다 같은 LAN의 Mac IP가 필요하므로 API_HOST로 지정한다.
  static String get baseUrl {
    const host = String.fromEnvironment('API_HOST');
    if (host.isNotEmpty) return 'http://$host:8000';
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
  }
```

- [ ] **Step 3: 정적 검사와 회귀 테스트를 돌린다**

```bash
cd app && flutter analyze && flutter test
```

기대: `No issues found!`, **7개 PASS**. 이 태스크는 `poller.dart`·`notifications.dart`를 건드리지 않으므로 개수와 결과가 태스크 2 직후와 같아야 한다.

- [ ] **Step 4: 커밋**

```bash
git add app/lib/api.dart
git commit -F - <<'EOF'
feat: Android 에뮬레이터 서버 주소 분기 — 기본값 10.0.2.2

에뮬레이터 안에서 127.0.0.1은 호스트 맥이 아니라 에뮬레이터 자신이라 서버에
영영 닿지 않는다. API_HOST가 이기는 우선순위는 그대로 두고 기본값만 갈랐다.

dart:io가 들어와 api.dart는 이후 웹 빌드가 불가능해진다. Android 전용으로 정한
지금은 맞는 선택이고, 웹을 붙이면 조건부 임포트로 갈라야 한다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 4: AndroidManifest — 평문 HTTP·권한·`tel` 가시성

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: 태스크 1이 만든 매니페스트. 태스크 3이 정한 `http://10.0.2.2:8000`(평문 HTTP라서 허용이 필요하다). `app/lib/screens/fall_detail.dart:65`의 `Uri(scheme: 'tel', path: number)`.
- Produces: 없음(설정 파일). 이 태스크 이후 매니페스트가 최종형이다.

**넣는 네 가지와 이유다.**

| 항목 | 위치 | 이유 |
|---|---|---|
| `POST_NOTIFICATIONS` 권한 | 루트 | Android 13+ 알림 필수. 태스크 2의 런타임 요청이 이 선언 없이는 아무 일도 안 한다 |
| `INTERNET` 권한 | 루트 | Flutter는 debug 매니페스트에만 넣는다. 릴리즈 빌드용으로 명시 필요 |
| `android:usesCleartextTraffic="true"` | `<application>` | 백엔드가 평문 HTTP. Android 9+가 기본 차단한다 |
| `tel` 인텐트 | 기존 `<queries>` 안 | Android 11+ 패키지 가시성. 119 발신 경로 |

`network_security_config.xml`로 특정 도메인만 여는 정밀한 방법은 **택하지 않았다.** 접속 대상이 그때그때 달라지는 LAN IP라 화이트리스트를 미리 쓸 수 없다. 이 프로젝트는 README에 명시된 대로 외부 배포 없는 LAN 전용 과제 제출물이다(설계 결정 4).

`tel` 가시성은 `fall_detail.dart`가 `canLaunchUrl` 없이 `launchUrl`을 직접 부르므로 없어도 동작할 여지가 있다. 그래도 넣는다. **119 발신은 이 앱에서 가장 중요한 동작**이고, 비용은 4줄이며, 실패했을 때 사용자가 잃는 것이 크다(설계 결정 5).

- [ ] **Step 1: 매니페스트를 통째로 바꾼다**

`app/android/app/src/main/AndroidManifest.xml`의 내용을 아래로 바꾼다. Flutter 템플릿 원문에서 바뀐 곳은 **네 군데뿐**이다 — 루트의 `uses-permission` 두 줄, `<application>`의 `android:label`과 `android:usesCleartextTraffic`, 그리고 기존 `<queries>` 블록 **안에** 더한 `tel` 인텐트. `<activity>` 블록과 영어 주석은 템플릿 원문 그대로 두므로 손대지 않는다.

`<queries>`를 새로 만들지 않는다. 템플릿이 이미 `PROCESS_TEXT`용으로 하나 갖고 있고, 매니페스트에 `<queries>`는 하나만 있어야 한다.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Android 13+는 런타임 알림 권한이 따로 있다. 없으면 낙상 알림이 조용히 안 뜬다. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <!-- Flutter는 이 권한을 debug 매니페스트에만 넣는다. 릴리즈 빌드에도 필요해 여기 명시한다. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:label="Fall Guardian"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <!-- 상세 화면의 119 발신(url_launcher). Android 11+는 이 선언이 없으면
             다이얼러 앱을 조회할 수 없어 launchUrl이 실패한다. -->
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
    </queries>
</manifest>
```

**`usesCleartextTraffic`에 주석을 달지 않는 이유.** `<application>` 태그 속성 사이에는 XML 주석을 넣을 수 없다. 이유는 태스크 5의 README와 `context-notes.md`에 남긴다.

- [ ] **Step 2: XML이 깨지지 않았는지 확인한다**

Android SDK가 없어 `aapt`로 매니페스트를 검증할 수 없다. 할 수 있는 것은 XML 문법 확인까지다.

```bash
xmllint --noout app/android/app/src/main/AndroidManifest.xml && echo "XML OK"
```

기대: `XML OK`. `xmllint`는 macOS에 기본 설치돼 있다.

- [ ] **Step 3: 넣기로 한 네 항목이 다 들어갔는지 센다**

```bash
grep -c "POST_NOTIFICATIONS\|android.permission.INTERNET\|usesCleartextTraffic\|android:scheme=\"tel\"" \
  app/android/app/src/main/AndroidManifest.xml
```

기대: `4`. 그리고 `<queries>`가 하나뿐인지도 본다.

```bash
grep -c "<queries>" app/android/app/src/main/AndroidManifest.xml    # 1이 나와야 한다
```

- [ ] **Step 4: Dart 쪽 회귀를 확인한다**

```bash
cd app && flutter analyze && flutter test
```

기대: `No issues found!`, **7개 PASS**. 매니페스트는 Dart 코드가 아니라 아무 영향이 없어야 한다. 달라지면 앞 태스크에서 뭔가 흘린 것이다.

- [ ] **Step 5: 커밋**

```bash
git add app/android/app/src/main/AndroidManifest.xml
git commit -F - <<'EOF'
feat: AndroidManifest — 평문 HTTP·알림/인터넷 권한·tel 가시성·앱 표시명

network_security_config.xml로 도메인을 좁히는 대신 usesCleartextTraffic을
전역으로 열었다. 접속 대상이 그때그때 달라지는 LAN IP라 화이트리스트를 미리
쓸 수 없다. 외부 배포 없는 LAN 전용 과제 제출물이라는 전제에서의 선택이다.

tel 가시성은 fall_detail이 canLaunchUrl 없이 launchUrl을 부르므로 없어도
동작할 여지가 있지만 넣었다. 119 발신이 이 앱에서 가장 중요한 동작이고
비용은 4줄이다. queries는 템플릿의 PROCESS_TEXT 블록 안에 더했다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 5: 문서 — 실행법·미검증 명시·라운드 기록

**Files:**
- Modify: `README.md` — 다이어그램(:31), "3. Flutter 앱" 절(:76-85), "## 테스트" 블록(:114), "알려진 한계"의 백그라운드 알림 항목(:128). 줄 번호는 **편집 전** 기준이다
- Modify: `docs/manual-verification.md` (맨 끝에 새 절)
- Modify: `checklist.md` (맨 끝에 새 절)
- Modify: `context-notes.md` (맨 끝에 새 절)

**Interfaces:**
- Consumes: 태스크 1~4의 완성된 동작.
- Produces: 없음(문서).

**줄 번호는 편집 전 기준이다.** Step 2가 "3. Flutter 앱" 절을 네 줄쯤 늘리므로 그 뒤 Step 3·4의 대상은 아래로 밀린다. 줄 번호로 찾지 말고 **아래 적힌 원문 문자열로 찾는다.**

- [ ] **Step 1: `README.md:31` 다이어그램의 플랫폼 표기를 고친다**

이 줄이 이제 틀렸다. 바꾸기 전.

```
       [보호자 페이지      [Flutter 앱(iOS)]
```

바꾼 뒤.

```
       [보호자 페이지      [Flutter 앱(iOS·Android)]
```

바로 아랫줄(`브라우저]          새 id 발견 시 로컬 알림  (app/)`)은 건드리지 않는다. 여는 대괄호 위치가 그대로라 정렬이 어긋나지 않는다.

- [ ] **Step 2: `README.md:76-85` "3. Flutter 앱" 절에 Android 실행법을 더한다**

절 전체를 바꾼다. 바꾸기 전.

````markdown
### 3. Flutter 앱

```bash
cd app
flutter pub get
flutter run                                   # iOS 시뮬레이터
flutter run --dart-define=API_HOST=<Mac IP>   # 실기기 — 같은 와이파이의 Mac IP
```

iOS 시뮬레이터는 서버 주소(`127.0.0.1:8000`)가 자동으로 잡힌다. 실기기는 같은 와이파이에 물린 Mac의 IP를 `API_HOST`로 넘긴다(`app/lib/api.dart`). 릴리즈 설치도 같다 — `flutter run --release --dart-define=API_HOST=<Mac IP>`.
````

바꾼 뒤.

````markdown
### 3. Flutter 앱

```bash
cd app
flutter pub get
flutter devices                               # 연결된 기기·시뮬레이터 확인
flutter run                                   # iOS 시뮬레이터
flutter run -d <에뮬레이터 id>                # Android 에뮬레이터 — 보통 emulator-5554
flutter run --dart-define=API_HOST=<Mac IP>   # 실기기 — 같은 와이파이의 Mac IP
```

시뮬레이터·에뮬레이터는 서버 주소가 자동으로 잡힌다. iOS 시뮬레이터는 `127.0.0.1:8000`, Android 에뮬레이터는 `10.0.2.2:8000`이다(에뮬레이터 안에서 `127.0.0.1`은 호스트 맥이 아니라 에뮬레이터 자신이다). 실기기는 양쪽 다 같은 와이파이에 물린 Mac의 IP를 `API_HOST`로 넘긴다(`app/lib/api.dart`). 릴리즈 설치도 같다 — `flutter run --release --dart-define=API_HOST=<Mac IP>`.

에뮬레이터 id는 환경마다 다르니 `flutter devices`로 확인한다.

> **Android는 빌드가 검증되지 않았다.** 이 코드를 쓴 맥에 Android SDK가 없어서(`flutter doctor`의 `[✗] Android toolchain`) `flutter analyze`와 `flutter test`까지만 통과시켰다. APK 빌드, 에뮬레이터에서의 `10.0.2.2` 접속, 알림 표시, Android 13+ 권한 팝업, `tel:` 발신은 **아직 한 번도 돌려보지 않았다.** Android Studio를 설치한 뒤 `docs/manual-verification.md` 7절을 밟아 확인한다. iOS는 종전대로 시뮬레이터 빌드까지 검증돼 있다.
````

- [ ] **Step 3: "## 테스트" 블록의 앱 테스트 개수를 고친다**

`cd app     && flutter test`로 시작하는 줄이다. 바꾸기 전.

```
cd app     && flutter test      # 4개 — 새 이벤트 판별
```

바꾼 뒤. `4개`를 `7개`로 바꾸고 무엇을 재는지 더한다.

```
cd app     && flutter test      # 7개 — 새 이벤트 판별 4, 알림 설정 3
```

같은 블록의 backend `36개`·web `20개`는 건드리지 않는다. 이번 변경이 만든 차이가 아니다.

- [ ] **Step 4: "알려진 한계"의 "앱은 백그라운드 알림이 없다" 항목을 고친다**

"앱은 iOS 전용이고(2026-07-24 Android 지원 제거)"가 이제 사실이 아니다. 항목 전체를 바꾼다. 바꾸기 전.

```
- **앱은 백그라운드 알림이 없다** — 데스크톱 브라우저는 보호자 페이지(guardian.html)의 표준 웹 푸시로 백그라운드에서도 알림을 받지만(2026-07-23 추가), 앱은 iOS 전용이고(2026-07-24 Android 지원 제거) iOS 네이티브 푸시(APNs)는 유료 개발자 계정이 필요해 범위 밖이다. 웹 푸시 구독은 보안 컨텍스트(https 또는 localhost)에서만 켤 수 있는데 이 프로젝트는 https로 배포하지 않으므로, 아이폰 홈 화면 PWA가 웹 푸시를 받는 경로도 배포 제거(2026-07-24)와 함께 막혔다. 보호자는 앱(또는 보호자 페이지)을 켜 두면 5초 폴링이 알린다.
```

바꾼 뒤. 앱이 iOS·Android 양쪽이 됐지만 **백그라운드 알림이 없다는 한계 자체는 그대로**라는 점을 분명히 한다.

```
- **앱은 백그라운드 알림이 없다** — 데스크톱 브라우저는 보호자 페이지(guardian.html)의 표준 웹 푸시로 백그라운드에서도 알림을 받지만(2026-07-23 추가), 앱은 iOS·Android 어느 쪽도 백그라운드 푸시가 없다. iOS 네이티브 푸시(APNs)는 유료 개발자 계정이 필요해 범위 밖이고, Android FCM은 2026-07-24 Android 지원 제거 때 스택 전체를 걷어냈다가 2026-07-27 Android 재지원에서도 되살리지 않았다(로컬 알림만 붙였다). 웹 푸시 구독은 보안 컨텍스트(https 또는 localhost)에서만 켤 수 있는데 이 프로젝트는 https로 배포하지 않으므로, 아이폰 홈 화면 PWA가 웹 푸시를 받는 경로도 배포 제거(2026-07-24)와 함께 막혔다. 보호자는 앱(또는 보호자 페이지)을 켜 두면 5초 폴링이 알린다.
```

- [ ] **Step 5: `docs/manual-verification.md`에 Android 절차를 더한다**

파일 맨 끝에 새 절로 붙인다. 현재 마지막 절이 `## 6`이므로 `## 7`이다. **먼저 확인하고**, 낙상 삭제 라운드가 이미 7을 썼다면 다음 번호를 쓴다.

```bash
grep -n "^## " docs/manual-verification.md | tail -1
```

기존 절들과 같은 체크박스 형식으로 붙인다.

````markdown
## 7. Android 지원 (2026-07-27 라운드) — SDK 설치 후 밟는다

**이 절은 아직 한 번도 실행되지 않았다.** 코드를 쓴 맥에 Android SDK가 없어 `flutter analyze`·`flutter test`까지만 통과시켰다. Android Studio를 설치한 사람이 여기부터 밟는다.

### 사전 준비

```bash
flutter doctor            # [✓] Android toolchain 이 떠야 한다
flutter devices           # 에뮬레이터 id 확인 (보통 emulator-5554)
cd app && flutter build apk --debug     # 여기서 처음으로 빌드가 검증된다
```

- [ ] `flutter doctor`의 Android toolchain이 `[✓]`다
- [ ] `flutter build apk --debug`가 성공한다 (**이 계획이 검증하지 못한 첫 번째 항목**)

### 에뮬레이터 — 서버 접속

백엔드(`:8000`)를 띄운 상태로 시작한다.

- [ ] `flutter run -d <에뮬레이터 id>`로 앱이 뜬다
- [ ] 앱 이름이 홈 화면에 **`Fall Guardian`**으로 보인다(`fall_guardian`이 아니다)
- [ ] 로그인 화면에서 로그인이 된다 — **`10.0.2.2`로 백엔드에 닿는다는 뜻이다.** "연결할 수 없습니다" 류가 뜨면 `app/lib/api.dart`의 분기를 먼저 본다
- [ ] 낙상 목록이 뜬다(평문 HTTP가 막히지 않았다는 뜻이다)

### 알림

- [ ] 앱 최초 실행에서 **알림 권한 팝업이 뜬다**(Android 13+). 안 뜨면 매니페스트의 `POST_NOTIFICATIONS`와 `Notifications.init()`의 `requestNotificationsPermission()`을 본다
- [ ] 감지 페이지에서 낙상을 하나 만들면 5초 안에 알림이 온다
- [ ] 그 알림이 **상단 배너(헤드업)로 뜬다.** 상태바에만 조용히 쌓이면 `Importance.max`/`Priority.high`가 안 먹은 것이다
- [ ] 알림 아이콘이 흰 사각형이 아니라 앱 아이콘 실루엣이다

### 119 발신

- [ ] 설정 화면에서 어르신 전화번호를 저장한다
- [ ] 낙상 상세 화면에서 전화 버튼을 누르면 **다이얼러가 열린다.** 아무 반응이 없으면 매니페스트 `<queries>`의 `tel` 인텐트를 본다(에뮬레이터에도 다이얼러가 있다)

### 실기기

- [ ] `flutter run --dart-define=API_HOST=<Mac IP>`로 같은 와이파이의 실기기에서 로그인이 된다
- [ ] 실기기에서도 알림이 헤드업으로 뜬다

### iOS 회귀

Android를 붙이면서 iOS가 상하지 않았는지 본다.

- [ ] iOS 시뮬레이터에서 앱이 그대로 뜬다(`flutter run`)
- [ ] iOS 알림이 그대로 뜬다(설정 값을 안 건드렸으므로 그대로여야 한다)
````

- [ ] **Step 6: `checklist.md`에 라운드 기록을 더한다**

파일 맨 끝에 새 절로 붙인다. 12절("Android 지원 제거")은 **그대로 둔다** — 지우면 왜 없앴다 다시 붙였는지가 사라진다.

현재 마지막이 `## 16`이므로 `## 17`이다. 먼저 확인하고, 다르면 다음 번호를 쓴다.

```bash
grep -n "^## " checklist.md | tail -1
```

```markdown
## 17. Flutter 앱 Android 지원 (2026-07-27)

12절에서 걷어냈던 Android를 다시 붙였다. 이번엔 FCM 없이 로컬 알림만이다. 경위는 context-notes.md "Android 재지원".

- [x] 설계 — 화면 9개는 그대로, 갈라지는 곳은 알림·서버 주소 둘뿐. Flutter Web은 범위 밖(guardian.html과 중복)
- [x] `android/` 생성 — `flutter create --platforms=android --org com.example`, 커밋 19개 파일
- [x] `flutter create` 부작용 3개 되돌림 — `.metadata`의 ios 항목 복원, `pubspec.lock` 22.0.1 유지, 템플릿 `test/widget_test.dart` 삭제
- [x] 알림 — 채널 `fall_alerts`, `Importance.max`/`Priority.high`, Android 13+ 런타임 권한 요청. iOS 설정 불변
- [x] 알림 테스트 3종 — Android 초기화 설정 존재·헤드업 값·iOS 설정 불변(조용히 실패하는 자리라 값으로 고정)
- [x] 서버 주소 — `API_HOST` 우선순위 유지, 기본값만 Android면 `10.0.2.2`
- [x] 매니페스트 — 평문 HTTP 전역 허용, `POST_NOTIFICATIONS`·`INTERNET`, `tel` 가시성, 표시명 `Fall Guardian`
- [x] 문서 — README 실행법·미검증 경고, 수동 검증 7절, 테스트 개수 4→7
- [x] 검증 — `flutter analyze` 무경고, `flutter test` 7개 통과
- [ ] **미검증** — APK 빌드·에뮬레이터 접속·알림 표시·권한 팝업·`tel` 발신. 이 맥에 Android SDK가 없다. 설치 후 `docs/manual-verification.md` 7절
```

마지막 항목은 **일부러 빈 체크박스**다. 다 됐다고 표시하면 안 된다.

- [ ] **Step 7: `context-notes.md`에 결정 근거를 더한다**

파일 맨 끝에 붙인다. 이 파일은 "왜 그렇게 했는가"를 남기는 곳이다. "Android 지원 제거(2026-07-24)" 절은 그대로 두고 그 뒤에 쌓는다.

```markdown
## Android 재지원 (2026-07-27)

2026-07-24에 걷어낸 Android를 다시 붙였다. 앞 절을 지우지 않고 남겨 둔다 — 없앴다 다시 붙인 경위 자체가 기록이다.

**되살린 것과 되살리지 않은 것이 다르다.** 제거 라운드는 `android/` 폴더와 FCM 스택을 함께 걷어냈다. 이번엔 폴더와 로컬 알림만 돌아왔고 **FCM은 되살리지 않았다.** Firebase 의존성·서비스 계정·백엔드 발송 경로가 전부 따라 들어오는데, 이 프로젝트가 실제로 얻는 것은 "앱이 꺼져 있을 때의 알림" 하나다. 보호자 페이지의 표준 웹 푸시가 그 자리를 이미 메우고 있어서 값이 비용을 못 넘는다. 그래서 앱은 여전히 켜 둬야 알림이 온다 — iOS와 같은 조건이다.

**작업의 실체는 만드는 것이 아니라 걷어내는 것이었다.** `lib/`의 Dart 파일 10개 중 9개가 이미 플랫폼 중립이었다. 화면 5개·`models.dart`·`poller.dart`·`main.dart`는 한 줄도 안 고쳤다. 실제로 갈라진 곳은 알림과 서버 주소 둘뿐이다. 화면을 고쳐야 하는 상황이 왔다면 그건 설계가 틀렸다는 신호였다.

**알림 설정을 테스트가 붙잡게 했다.** `InitializationSettings`에 `android` 필드가 없으면 안드로이드에서 예외도 로그도 없이 알림이 그냥 안 뜬다. 낙상 앱에서 알림이 안 뜨면 앱이 하는 일이 없는데, `flutter analyze`는 이걸 못 잡고 이 맥엔 Android SDK가 없어 실기기 검증도 못 한다. 순수 단위 테스트가 유일하게 가능한 검증이라 `_details`의 밑줄을 떼고 `settings`를 상수로 꺼냈다(`@visibleForTesting`). 테스트 때문에 공개 범위를 넓힌 것이고, 조용히 실패하는 버그를 잡는 값이 그 비용보다 컸다.

**Flutter Web은 기술이 아니라 중복 때문에 안 했다.** 검토 중 `flutter_local_notifications` v22가 웹을 지원한다는 것을 확인했다(`flutter_local_notifications_web` 1.0.0, `InitializationSettings.web` 필드 존재). 장벽은 없었다. 다만 `guardian.html`이 낙상 목록·방 관리·연락처를 이미 하고 **웹 푸시까지** 된다. Flutter Web을 붙이면 보호자 웹 클라이언트가 2개가 되고 새 쪽이 오히려 기능이 적다.

**`10.0.2.2` 분기의 대가는 웹 빌드다.** `Platform.isAndroid`를 쓰느라 `api.dart`에 `dart:io`가 들어왔고, 이 파일은 이제 웹으로 컴파일되지 않는다. Android 전용으로 정한 지금은 맞는 선택이지만, 나중에 웹을 붙이면 조건부 임포트(`dart:io`/`dart:html`)로 갈라야 한다. 위 문단에서 웹을 안 하기로 한 것과 한 세트인 결정이다.

**평문 HTTP는 도메인을 좁히지 않고 전역으로 열었다.** 정밀한 방법은 `network_security_config.xml`에 특정 도메인만 쓰는 것인데, 접속 대상이 그때그때 달라지는 LAN IP라 화이트리스트를 미리 쓸 수가 없다. 매번 바뀌는 값을 넣어 둔 설정 파일은 정밀해 보일 뿐 정밀하지 않다. `usesCleartextTraffic="true"` 한 줄에 이유를 문서로 남기는 쪽이 정직하다. 외부 배포 없는 LAN 전용 과제 제출물이라는 전제에서만 성립하는 선택이다.

**`flutter create`가 조용히 망가뜨리는 것이 셋 있었다.** 실행 후 `git status`로 잡아냈다. ① `.metadata`의 `migration.platforms`에서 `ios` 항목이 `android`로 **대체**된다(추가가 아니다) — 손으로 되살렸다. ② 같이 도는 `pub get`이 `flutter_local_notifications`를 22.0.1 → 22.2.0으로 올린다 — 설계의 API 확인을 22.0.1 소스로 했으므로 lock을 되돌렸다. ③ 카운터 앱 예제 `test/widget_test.dart`를 만드는데, 없는 `MyApp`을 참조해 `flutter test` 전체를 컴파일 에러로 죽인다 — 삭제했다. 셋 다 "새 폴더만 생겼겠지"라고 넘어가면 나중에 이상한 자리에서 터진다.

**미검증인 채로 끝냈고 그걸 문서에 박아 뒀다.** 이 맥에 Android SDK가 없어 APK 빌드·에뮬레이터 접속·알림 표시·권한 팝업·`tel` 발신이 전부 미검증이다. 사용자가 이 상태를 알고 선택했다. "될 것이다"로 넘기지 않고 README 실행 절과 `checklist.md` 17절(체크 안 된 항목), `docs/manual-verification.md` 7절 세 곳에 남겼다. SDK를 설치한 사람이 7절부터 밟으면 된다.
```

- [ ] **Step 8: 커밋**

```bash
git add README.md docs/manual-verification.md checklist.md context-notes.md
git commit -F - <<'EOF'
docs: Android 지원 라운드 기록 — 실행법·미검증 명시·결정 근거

README에 에뮬레이터/실기기 실행법과 "빌드 미검증" 경고를 넣었다. Android SDK가
없어 analyze와 test까지만 통과시켰고, 나머지는 manual-verification 7절에
체크리스트로 남겨 SDK 설치 후 밟게 했다.

2026-07-24 제거 기록(checklist 12절, context-notes)은 지우지 않고 그 뒤에
"왜 다시 붙였고 FCM은 왜 안 되살렸는지"를 덧붙였다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## 최종 검증

다섯 태스크가 끝난 뒤 저장소 루트에서 한 번에 돌린다.

```bash
cd app && flutter analyze          # No issues found!
cd app && flutter test             # 7개 PASS
```

그리고 **설계 5절의 완료 기준을 git으로 직접 확인한다.**

```bash
# 1. android/가 생겼고 .metadata에 android·ios가 다 있다
ls app/android/app/src/main/AndroidManifest.xml
grep -c "platform:" app/.metadata                        # 3

# 2. lib/ 중 바뀐 파일이 notifications.dart와 api.dart 둘뿐이다
git diff --name-only HEAD~5 -- app/lib/                   # 정확히 2줄

# 3. ios/와 pubspec은 한 줄도 안 바뀌었다
git diff --name-only HEAD~5 -- app/ios/ app/pubspec.yaml app/pubspec.lock   # 빈 출력
```

세 검사 중 하나라도 어긋나면 멈추고 원인을 본다. 2번이 3줄 이상이거나 3번이 비어 있지 않으면 **설계가 틀렸거나 실행이 샌 것**이다.

`HEAD~5`는 이 계획의 다섯 커밋을 전제로 한 값이다. 커밋을 더 쪼갰거나 중간에 다른 커밋이 끼었으면 태스크 1 직전 커밋의 해시를 쓴다.

**완료 보고에 반드시 넣을 문장.** "Android SDK가 없어 APK 빌드와 에뮬레이터/실기기 동작(알림 표시, 13+ 권한 팝업, `10.0.2.2` 접속, `tel:` 발신)은 검증하지 못했다. `docs/manual-verification.md` 7절에 절차를 남겼다." 이 사실을 빼고 "완료"라고만 보고하면 안 된다.
