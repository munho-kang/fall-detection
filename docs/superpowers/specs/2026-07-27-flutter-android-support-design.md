# Flutter 앱 Android 지원 설계 — 화면은 그대로, 갈라지는 두 곳만

2026-07-27. iOS만 구성돼 있던 `app/`에 Android 플랫폼을 추가한다.
브레인스토밍 결정 기록이며 구현 계획의 입력이 된다.

## 1. 출발점

`app/.metadata`가 추적하는 플랫폼이 `root`와 `ios` 둘뿐이다. `android/` 폴더가 없다.
`flutter create`를 iOS만 지정해 만든 상태다.

반면 `lib/`의 Dart 파일 10개 중 **9개는 완전히 플랫폼 중립적이다.**
화면 5개(`login`·`signup`·`fall_list`·`fall_detail`·`settings`), `models.dart`,
`poller.dart`, `main.dart`는 한 줄도 고칠 필요가 없다.
실제로 플랫폼이 갈라지는 지점은 **알림과 서버 주소 두 곳**뿐이다.

이 설계의 요점은 새로 만드는 것이 아니라 **재사용을 막고 있는 두 지점을 걷어내는 것**이다.

## 2. 범위와 결정

포함한다.

1. **`android/` 폴더 생성** — `flutter create --platforms=android`
2. **`lib/notifications.dart`** — Android 알림 경로 추가
3. **`lib/api.dart`** — Android 에뮬레이터 호스트 분기
4. **`AndroidManifest.xml`** — 평문 HTTP·알림 권한·인터넷 권한·`tel` 가시성
5. **`README.md`** — Android 실행법과 미검증 사실 명시

범위 밖.

- **Flutter Web** — `web/guardian.html`이 낙상 목록·방 관리·연락처를 이미 하고 있고
  Flutter 앱에 없는 **웹 푸시**까지 된다. Flutter Web을 붙이면 보호자 웹 클라이언트가
  2개가 되고 새 쪽이 오히려 기능이 적다. 중복을 만들지 않는다.
- **`web/`·`backend/` 수정** — 백엔드 CORS는 이미 `addAllowedOriginPattern("*")`이라
  Android에서 손댈 것이 없다.
- **기존 화면 코드 수정** — 재사용이 이 작업의 요점이다. 화면을 고쳐야 한다면 설계가 틀린 것이다.
- **macOS·Windows·Linux 데스크톱** — 요청에 없다.

### 결정 1 — Flutter Web은 하지 않는다

검토 시점에 `flutter_local_notifications` v22가 웹을 지원한다는 것을 확인했다
(`flutter_local_notifications_web` 1.0.0, `InitializationSettings.web` 필드 존재).
즉 기술적 장벽 때문이 아니다.

하지 않는 이유는 **중복**이다. `guardian.html`이 같은 일을 이미 하고 더 잘 한다.
웹 푸시는 화면이 꺼져 있어도 알림이 오지만, Flutter Web 클라이언트를 새로 만들면
5초 폴링부터 다시 시작해야 한다.

### 결정 2 — 알림은 조용히 실패하는 버그다

현재 `Notifications.init()`은 `InitializationSettings(iOS: ...)`만 넘긴다.
`android` 필드가 null이면 안드로이드에서 **예외도 로그도 없이 알림이 그냥 안 뜬다.**
낙상 감지 앱에서 알림이 안 뜨는 것은 앱이 하는 일이 없다는 뜻이다.

그래서 이 항목이 Android 지원의 핵심이며, 폴더 생성보다 우선순위가 높다.

채널 중요도는 `Importance.max` / `Priority.high`로 둔다.
낙상은 헤드업 알림으로 즉시 떠야 하는 종류의 알림이다.

### 결정 3 — `10.0.2.2` 분기는 `Platform.isAndroid`로 한다

에뮬레이터에서 `127.0.0.1`은 호스트 맥이 아니라 **에뮬레이터 자신**을 가리킨다.
서버에 영영 닿지 않는다. 안드로이드 에뮬레이터는 호스트를 `10.0.2.2`로 본다.

우선순위는 기존 규칙을 유지한다. `API_HOST`가 주어지면 그것이 이긴다(실기기 경로).
없을 때의 기본값만 플랫폼별로 갈린다.

대가가 하나 있다. `dart:io` 임포트가 생겨 **`api.dart`는 이후 웹 빌드가 불가능해진다.**
Android 전용으로 정한 지금은 맞는 선택이지만, 나중에 웹을 붙이면 조건부 임포트
(`dart:io` / `dart:html` 분기)로 갈라야 한다. 그때의 비용으로 기록해 둔다.

### 결정 4 — 평문 HTTP는 전역 허용한다

백엔드가 `http://<Mac IP>:8000`이고 Android 9+는 평문 HTTP를 기본 차단한다.

정밀한 방법은 `network_security_config.xml`로 특정 도메인만 허용하는 것이다.
택하지 않았다. 접속 대상이 **그때그때 달라지는 LAN IP**라서 화이트리스트를 미리 쓸 수 없다.
`usesCleartextTraffic="true"` 한 줄에 이유를 주석으로 남기는 쪽이 정직하다.

이 프로젝트는 README에 명시된 대로 외부 배포 없는 LAN 전용 과제 제출물이다.

### 결정 5 — `tel` 가시성을 매니페스트에 넣는다

Android 11+는 패키지 가시성 제약이 있어 `<queries>` 선언 없이는 다른 앱의 인텐트를
조회할 수 없다. `url_launcher` README가 요구하는 설정이다.

`fall_detail.dart`는 `canLaunchUrl` 없이 `launchUrl`을 직접 호출하므로 없어도 동작할
여지가 있다. 그래도 넣는다. **119 발신은 이 앱에서 가장 중요한 동작**이고,
비용은 4줄이며, 실패했을 때 사용자가 잃는 것이 크다.

## 3. 변경 상세

### 3.1 `android/` 폴더

```bash
cd app
flutter create --platforms=android --org com.example .
```

iOS 번들 ID가 `com.example.fallGuardian`이므로 org는 `com.example`을 유지한다.
Android 패키지는 `com.example.fall_guardian`이 된다.
(iOS의 `fallGuardian`과 철자가 다르지만 Android는 snake_case가 관례이고,
두 플랫폼의 애플리케이션 ID는 서로 독립이다.)

실행 후 `git status`로 `lib/`·`ios/`·`pubspec.yaml`이 건드려지지 않았는지 확인한다.
건드려졌다면 되돌린다.

앱 표시명(`android:label`)은 iOS의 `CFBundleDisplayName`과 맞춰 `Fall Guardian`으로 둔다.

### 3.2 `lib/notifications.dart`

확인한 v22 API다(pub 캐시에서 시그니처 직접 확인).

| 대상 | 시그니처 |
|---|---|
| 초기화 설정 | `AndroidInitializationSettings(String defaultIcon)` — 위치 인자 |
| 알림 상세 | `AndroidNotificationDetails(channelId, channelName, {importance, priority, ...})` |
| 권한 요청 | `AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission()` → `Future<bool?>` |
| 플러그인 획득 | `_plugin.resolvePlatformSpecificImplementation<T>()` |

- `InitializationSettings`에 `android: AndroidInitializationSettings('@mipmap/ic_launcher')` 추가
- `NotificationDetails`에 `android: AndroidNotificationDetails('fall_alerts', '낙상 알림', importance: Importance.max, priority: Priority.high)` 추가
- `init()`에서 Android 13+ 런타임 권한 요청
- **iOS 설정은 그대로 둔다**

### 3.3 `lib/api.dart`

`baseUrl` 게터만 바꾼다. 나머지 메서드는 손대지 않는다.

우선순위. `API_HOST` → (Android면 `10.0.2.2:8000`, 아니면 `127.0.0.1:8000`).

### 3.4 `android/app/src/main/AndroidManifest.xml`

| 항목 | 위치 | 이유 |
|---|---|---|
| `android:usesCleartextTraffic="true"` | `<application>` | 백엔드가 평문 HTTP. Android 9+ 기본 차단 |
| `POST_NOTIFICATIONS` 권한 | 루트 | Android 13+ 알림 필수 |
| `INTERNET` 권한 | 루트 | Flutter는 debug 매니페스트에만 넣는다. 릴리즈용으로 명시 필요 |
| `<queries>` + `tel` 인텐트 | 루트 | Android 11+ 패키지 가시성 (결정 5) |

### 3.5 `README.md`

"3. Flutter 앱" 절에 Android 실행 명령을 추가한다.

```bash
flutter devices                               # 연결된 기기 확인
flutter run -d <에뮬레이터 id>                # 에뮬레이터 — 10.0.2.2로 자동 연결
flutter run --dart-define=API_HOST=<Mac IP>   # 실기기 — 같은 와이파이의 Mac IP
```

에뮬레이터 id는 보통 `emulator-5554` 꼴이지만 환경마다 다르므로 `flutter devices`로 확인한다.

**Android SDK 미설치로 빌드 미검증**임을 같은 절에 명시한다(4절 참조).

## 4. 검증

| 명령 | 기대 | 가능 여부 |
|---|---|---|
| `flutter analyze` | 무경고 | 가능 |
| `flutter test` | 기존 4개 통과 | 가능 |
| `flutter build apk` | 성공 | **불가 — Android SDK 없음** |
| 에뮬레이터 실행·알림 수신 | 동작 | **불가 — Android SDK 없음** |

이 맥에는 Android SDK가 없다(`flutter doctor`에서 `[✗] Android toolchain`).
따라서 **APK 빌드와 실기기/에뮬레이터 동작은 검증되지 않은 채로 남는다.**
사용자가 이 상태를 알고 선택했다. 완료 보고에 "미검증"을 반드시 명시한다.

검증되지 않은 항목은 특히 다음이다.

- Android 알림이 실제로 뜨는지
- Android 13+ 권한 팝업이 뜨는지
- `10.0.2.2`로 에뮬레이터가 백엔드에 닿는지
- `tel:` 발신이 다이얼러를 여는지

Android Studio를 설치하면 위 4개를 그때 검증한다.

## 5. 완료 기준

- `app/android/` 존재, `.metadata`에 `android` 플랫폼 등록
- `flutter analyze` 무경고
- `flutter test` 4개 통과
- `lib/` 중 `notifications.dart`·`api.dart` 외 파일 변경 없음
- `ios/` 변경 없음
- README에 Android 실행법과 미검증 사실 기재
