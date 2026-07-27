# 다크모드 색 정리와 낙상 발생 모달 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 화면 10개의 하드코딩된 라이트 전용 색을 테마 색으로 옮겨 다크모드를 정상화하고, 새 낙상이 감지되면 화면 한가운데 "사고 발생" 창을 띄운다.

**Architecture:** `app_theme.dart`의 `ColorScheme`에 빠져 있던 다크 분기 5개를 채우고, 화면들이 `AppColors.*` 상수 대신 `Theme.of(context).colorScheme.*`을 읽게 바꾼다. `Scaffold`·`AppBar` 배경은 테마에 이미 올바른 값이 있으므로 치환이 아니라 **삭제**한다. 모달은 `MainShell`이 대기열을 들고 폴러의 `fresh` 리스트를 받아 루트 네비게이터에 `showDialog`를 순차로 띄운다.

**Tech Stack:** Flutter (Dart SDK ^3.12.0), Material 3 `ColorScheme`, `flutter_test` 위젯 테스트, `shared_preferences` (테스트에서 mock).

## Global Constraints

전 과제에 적용된다. 각 과제의 요구사항에 이 절이 암묵적으로 포함된다.

- **라이트 모드 외관은 그대로 유지한다.** 모든 치환은 라이트에서 같은 값으로 떨어지도록 고른 것이다. 라이트에서 색이 달라 보이면 그 치환은 틀린 것이다.
- **`AppColors.primary`(`0xFF00695C`)·`onPrimary`·`error`는 치환하지 않는다.** 36곳(primary 18, onPrimary 7, error 11)이 그대로 남는다. 딥 틸을 다크에서 뒤집으면 브랜드 인상이 바뀌고 요청 범위를 넘는다.
- **`app/lib/screens/splash.dart`는 손대지 않는다.** 배경이 `AppColors.primary`인 브랜드 화면이라 양쪽 모드에서 틸을 유지한다. `AppColors.` 4곳이 남는 것이 정상이다.
- **모달의 "확인"은 창만 닫는다.** `api.acknowledge()`를 부르지 않는다. "봤다"와 "확인 처리했다"는 분리한다.
- **새 소스 파일 첫 줄은 역할을 적은 한국어 한 줄 주석이다.** (`CLAUDE.md` 6절)
- **한국어 문장은 마침표로 끝낸다.** 다음 줄이 목록이어도 콜론으로 끝내지 않는다. (`CLAUDE.md` 5절)
- **기존 24개 테스트(5개 파일)는 계속 통과해야 한다.** 시작 시점 상태는 `flutter test` 24 passed, `flutter analyze` No issues found다.
- **`flutter analyze`는 무경고를 유지한다.** `const`를 떼면 `prefer_const_constructors`가, 안 쓰는 import가 남으면 `unused_import`가 잡는다. 둘 다 이번 작업에서 실제로 발생한다.
- **커밋은 과제 단위로 한다.** 각 과제 마지막 단계가 커밋이다.

---

## 사전 지식 — 이 코드베이스에서 알아야 할 것

**`AppColors`는 라이트 전용 상수 모음이다.** `app/lib/app_theme.dart`에 있고, 이름이 `ColorScheme`의 슬롯 이름과 일치한다(`onSurface`, `outlineVariant`, …). 화면이 이 상수를 직접 쓰면 다크 테마가 적용돼도 라이트 값이 그려진다. 이번 작업의 핵심은 그 참조를 테마 조회로 옮기는 것이다.

**테마는 이미 옳다.** `buildAppTheme(dark: true, ...)`는 `scaffoldBackgroundColor`(`0xFF131716`)와 `appBarTheme`을 이미 밝기별로 분기해 둔다. 그래서 화면의 `Scaffold(backgroundColor: ...)`·`AppBar(backgroundColor:, foregroundColor:)`는 지우기만 하면 올바른 값으로 떨어진다.

**`const` 위젯은 `Theme.of(context)`를 못 쓴다.** `const Icon(..., color: AppColors.onSurfaceVariant)`를 테마 조회로 바꾸면 `const`를 떼야 컴파일된다. 반대로 `const`를 떼면 안 되는 곳(치환 대상이 아닌 `AppColors.primary` 등)에서 `const`를 떼면 `prefer_const_constructors` 경고가 난다. 기계적이지만 방향이 두 개다.

**작업량 실측 (2026-07-28).**

| 항목 | 수 |
|---|---|
| `AppColors.*` 참조 (10개 파일, splash 제외) | 145 |
| ├ 삭제 (`Scaffold`·`AppBar` 배경·전경) | 25 |
| ├ 그대로 (`primary`·`onPrimary`·`error`) | 36 |
| └ 치환 | 84 |
| `AppColors`를 안 거치는 원시 색 리터럴 | 12 |

**원시 색 리터럴 12곳은 전부 비활성 상태 색이다.** `Color(0x1F191C1B)`·`Color(0x61191C1B)`인데 `191C1B`가 라이트 `onSurface`와 같은 값이고 알파 `0x1F`·`0x61`은 Material의 비활성 배경 12%·전경 38%다. 그래서 `colorScheme.onSurface.withValues(alpha: 0.12 / 0.38)`으로 바꾸면 의미가 보존되면서 밝기를 따라간다.

**손대지 않는 죽은 코드.** `AppColors.pageBg`·`AppColors.inverseSurface`는 어디에서도 안 쓰인다. 이번 요청과 무관하므로 지우지 않는다.

### 줄 번호 읽는 법 — 삭제 뒤에는 밀린다

이 계획의 모든 줄 번호는 **작업 시작 시점(커밋 `2283a5c`)의 파일 기준**이다. 각 과제는 `Scaffold`·`AppBar` 줄을 먼저 지우므로, **그 뒤에 나오는 줄 번호는 지운 줄 수만큼 위로 밀린다.**

| 파일 | 지우는 줄 수 | 그 뒤 표의 줄 번호 보정 |
|---|---|---|
| `home` · `settings` · `fall_list` · `profile` · `fall_detail` · `room_management` · `login` · `signup` | 3 | −3 |
| `start` | 1 | −1 |

**줄 번호는 길잡이고, 맞춰야 할 것은 표의 "지금" 칸 원문이다.** 원문이 파일에서 유일하지 않은 경우가 하나 있다 — `settings.dart`의 `const Divider(height: 1, color: AppColors.outlineVariant),`는 두 군데(144·150)에 똑같이 있다. 둘 다 같은 결과로 바뀌므로 전체 치환해도 된다.

### 스펙에서 바뀐 것 두 가지

계획을 짜며 실측한 결과 스펙(`docs/superpowers/specs/2026-07-28-dark-mode-fall-alert-design.md`)과 달라진 점이다. 스펙을 읽고 오는 사람이 혼란스럽지 않도록 적어 둔다.

1. **스펙 §4 표에 빠진 자리가 하나 있다.** `profile.dart:170`의 `Border.all(color: AppColors.surface, width: 2)`는 `Scaffold`·`AppBar` 배경이 아니라 카메라 배지를 둘러싼 링 색이다. 삭제 대상이 아니라 치환 대상이고, `colorScheme.surface`가 아니라 **`Theme.of(context).scaffoldBackgroundColor`**로 간다 — 링은 페이지 배경을 오려낸 것처럼 보여야 하는데 다크에서 둘이 다르다(`0xFF131716` vs `0xFF1B1F1E`). 라이트에서는 두 값이 같아 외관이 안 변한다. 과제 4에서 처리한다.
2. **스펙 §6의 "pending timer 실패" 경고는 이 Flutter 버전에서 성립하지 않는다.** 실측해 보니 `testWidgets` 종료 시 프레임워크가 트리를 dispose하고 `MainShell.dispose()`가 `_poller.stop()`을 태우므로, 창이 열린 채 끝내도 통과한다. 그래서 계획에 `pumpWidget(const SizedBox())` 정리 줄을 넣지 않는다. **대신 진짜 함정이 따로 있다** — 과제 8의 `SharedPreferences.setMockInitialValues`다. 없으면 `Notifications.show`의 `await`가 안 풀려 예외도 없이 창이 영영 안 뜬다(실측: "Found 0 widgets", 예외 없음).

---

## File Structure

| 파일 | 역할 | 과제 |
|---|---|---|
| `app/lib/app_theme.dart` | 다크 팔레트 5색 추가, `dangerColors` 추가 | 1 |
| `app/test/app_theme_test.dart` | 신규. 밝기 분기 단위 테스트 | 1 |
| `app/lib/screens/home.dart` | 24곳. 헬퍼 2개에 `context` 추가 | 2 |
| `app/test/dark_mode_test.dart` | 신규. 화면별 다크 색 카나리아. 과제 2~6이 이어서 채운다 | 2~6 |
| `app/lib/screens/settings.dart` | 19곳 | 3 |
| `app/lib/screens/fall_list.dart` | 15곳 | 3 |
| `app/lib/screens/profile.dart` | 21곳 + 스펙 공백 1곳 | 4 |
| `app/lib/screens/fall_detail.dart` | 17곳 + 원시 리터럴 7곳 | 5 |
| `app/lib/screens/room_management.dart` | 15곳 | 6 |
| `app/lib/screens/start.dart` | 7곳 | 6 |
| `app/lib/screens/login.dart` | 13곳 + 원시 리터럴 3곳 | 6 |
| `app/lib/screens/signup.dart` | 13곳 + 원시 리터럴 2곳 | 6 |
| `app/lib/screens/fall_alert_dialog.dart` | **신규.** 사고 발생 창 위젯 하나 | 7 |
| `app/test/fall_alert_dialog_test.dart` | 신규. 표시 내용·유일한 출구 검증 | 7 |
| `app/lib/screens/main_shell.dart` | 대기열·순차 표시 배선 + `AppColors` 1곳 | 8 |
| `app/test/main_shell_alert_test.dart` | 신규. 순차 표시·안 띄우는 경우 | 8 |

**테스트 파일 배치는 스펙과 다르다.** 스펙 §6은 화면 단위 검증을 `app_theme_test.dart`에 넣으라고 했는데, 순수 단위 테스트와 위젯 테스트를 한 파일에 섞게 된다. `app_theme_test.dart`는 테마 단위 테스트만 두고 화면 카나리아는 `dark_mode_test.dart`로 분리한다. 검증 범위는 스펙(설정 화면 1개)보다 넓다(5개 화면).

---

## Task 1: `app_theme.dart` — 다크 팔레트와 `dangerColors`

**Files:**
- Modify: `app/lib/app_theme.dart:63-80` (`ColorScheme.fromSeed` 인자), 파일 끝에 함수 1개 추가
- Test: `app/test/app_theme_test.dart` (신규)

**Interfaces:**
- Consumes: 없음. 이 과제가 출발점이다.
- Produces:
  - `ThemeData buildAppTheme({required bool dark, required TextScale scale})` — 시그니처 변경 없음. 과제 2~6의 테스트가 쓴다.
  - `({Color bg, Color fg}) dangerColors(Brightness brightness)` — 신규. 과제 4·5·6이 쓴다. 레코드 필드 이름은 `bg`·`fg`다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/app_theme_test.dart`를 새로 만든다.

```dart
// 밝기 분기 검증 — 이번 버그의 정체가 "분기 누락"이라 빠지면 여기서 바로 실패한다

import 'package:fall_guardian/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final light = buildAppTheme(dark: false, scale: TextScale.normal);
  final dark = buildAppTheme(dark: true, scale: TextScale.normal);

  test('페이지 배경이 밝기별로 다르다', () {
    expect(light.scaffoldBackgroundColor, const Color(0xFFF4F6F6));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF131716));
  });

  test('구분선·컨테이너 색이 밝기별로 다르다', () {
    expect(dark.colorScheme.outlineVariant, isNot(light.colorScheme.outlineVariant));
    expect(dark.colorScheme.primaryContainer, isNot(light.colorScheme.primaryContainer));
    expect(dark.colorScheme.onPrimaryContainer, isNot(light.colorScheme.onPrimaryContainer));
    expect(dark.colorScheme.errorContainer, isNot(light.colorScheme.errorContainer));
    expect(dark.colorScheme.onErrorContainer, isNot(light.colorScheme.onErrorContainer));
  });

  test('라이트 값은 그대로다', () {
    expect(light.colorScheme.outlineVariant, const Color(0xFFC0C9C6));
    expect(light.colorScheme.primaryContainer, const Color(0xFFD3E0DC));
    expect(light.colorScheme.onPrimaryContainer, const Color(0xFF1F3833));
    expect(light.colorScheme.errorContainer, const Color(0xFFFBE3DD));
    expect(light.colorScheme.onErrorContainer, const Color(0xFFD64A2F));
  });

  test('브랜드 색은 양쪽 공통이다', () {
    expect(dark.colorScheme.primary, light.colorScheme.primary);
    expect(dark.colorScheme.onPrimary, light.colorScheme.onPrimary);
    expect(dark.colorScheme.error, light.colorScheme.error);
    expect(dark.colorScheme.outline, light.colorScheme.outline);
  });

  test('dangerColors가 밝기별로 다른 값을 준다', () {
    final l = dangerColors(Brightness.light);
    final d = dangerColors(Brightness.dark);

    expect(l.bg, const Color(0xFFF7DAD2));
    expect(l.fg, const Color(0xFFA03920));
    expect(d.bg, isNot(l.bg));
    expect(d.fg, isNot(l.fg));
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/app_theme_test.dart`

Expected: FAIL. 컴파일 단계에서 `Error: The function 'dangerColors' isn't defined.`이 난다. `dangerColors`를 정의하면 그다음엔 `구분선·컨테이너 색이 밝기별로 다르다`가 실패한다(지금은 라이트 값 하나로 고정이라 `isNot`이 깨진다).

- [ ] **Step 3: 다크 분기 5개 추가**

`app/lib/app_theme.dart`의 `ColorScheme.fromSeed` 호출에서 세 줄을 바꾼다. 기존 인라인 분기 스타일을 그대로 잇는다.

`app/lib/app_theme.dart:68-69`:

```dart
    primaryContainer: dark ? const Color(0xFF1E4640) : AppColors.primaryContainer,
    onPrimaryContainer: dark ? const Color(0xFFB8E7DD) : AppColors.onPrimaryContainer,
```

`app/lib/app_theme.dart:76`:

```dart
    outlineVariant: dark ? const Color(0xFF3A4442) : AppColors.outlineVariant,
```

`app/lib/app_theme.dart:78-79`:

```dart
    errorContainer: dark ? const Color(0xFF4A241C) : AppColors.errorContainer,
    onErrorContainer: dark ? const Color(0xFFFFB4A0) : AppColors.onErrorContainer,
```

`primary`·`onPrimary`·`surface`·`surfaceContainer`·`surfaceContainerHigh`·`onSurface`·`onSurfaceVariant`·`outline`·`error` 줄은 건드리지 않는다.

- [ ] **Step 4: `dangerColors` 추가**

`app/lib/app_theme.dart` 파일 맨 끝, `buildAppTheme`의 닫는 중괄호 다음에 붙인다.

```dart

// 파괴적 동작(기록 삭제 · 방 삭제 · 회원 탈퇴) 색 — ColorScheme에 대응 슬롯이 없어 밝기로 직접 고른다.
// BuildContext가 아니라 Brightness를 받으므로 위젯 없이 단위 테스트할 수 있다.
({Color bg, Color fg}) dangerColors(Brightness brightness) => brightness == Brightness.dark
    ? (bg: const Color(0xFF43201A), fg: const Color(0xFFFFB4A0))
    : (bg: const Color(0xFFF7DAD2), fg: const Color(0xFFA03920));
```

`AppColors.dangerBg`·`dangerFg` 상수는 지우지 않는다. 과제 4~6이 마지막 참조를 걷어낸 뒤 과제 9에서 정리한다.

- [ ] **Step 5: 통과 확인**

Run: `cd app && flutter test test/app_theme_test.dart && flutter analyze`

Expected: `+5: All tests passed!` / `No issues found!`

- [ ] **Step 6: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/app_theme.dart app/test/app_theme_test.dart
git commit -m "feat: 다크 팔레트 5색 분기와 dangerColors 헬퍼"
```

---

## Task 2: `home.dart` — 24곳

**Files:**
- Modify: `app/lib/screens/home.dart`
- Test: `app/test/dark_mode_test.dart` (신규)

**Interfaces:**
- Consumes: `buildAppTheme(dark:, scale:)`, `TextScale` (과제 1).
- Produces: `Widget _addRoomCard(BuildContext context)` · `Widget _connectionBanner(BuildContext context)` — 두 private 헬퍼에 `context` 매개변수가 생긴다. 파일 안에서만 쓰이므로 외부 영향은 없다.

**이 파일이 까다로운 이유.** `HomeScreen`은 `StatelessWidget`이라 `State.context`가 없다. `_addRoomCard()`·`_connectionBanner()`는 `context`를 안 받는 헬퍼인데 안에서 `primaryContainer`·`errorContainer`를 쓴다. 두 헬퍼에 `BuildContext`를 넘겨야 한다. 나머지 헬퍼(`_titleStyle`·`_alertCard`·`_alertTile`)는 이미 `context`를 받는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/dark_mode_test.dart`를 새로 만든다. 과제 3~6이 이 파일에 테스트를 덧붙인다.

```dart
// 다크 테마로 각 화면을 띄워 대표 글자색이 다크 값인지 본다 —
// 라이트 상수가 화면에 하드코딩돼 있으면 여기서 잡힌다

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 다크 테마의 값 — app_theme.dart와 맞춘다
const darkOnSurface = Color(0xFFE2E6E5);
const darkOnSurfaceVariant = Color(0xFFBFC9C6);
const darkOnPrimaryContainer = Color(0xFFB8E7DD);

Future<void> pumpDark(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(dark: true, scale: TextScale.normal),
    home: screen,
  ));
  await tester.pump();
}

Color? colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('홈 — 섹션 제목과 방 추가 배너가 다크 글자색이다', (tester) async {
    await pumpDark(
      tester,
      HomeScreen(
        events: const [],
        rooms: const [],
        loadingEvents: false,
        loadingRooms: false,
        connectionError: null,
        unreadCount: 0,
        onGoNotifications: () {},
        onGoSettings: () {},
        onChangeTab: (_) {},
        api: Api(),
        onLogout: () {},
      ),
    );

    // 카드 밖 페이지 배경 위에 바로 놓인 글자 — 배경만 고치면 사라지는 자리다
    expect(colorOf(tester, '확인하지 않은 알림'), darkOnSurface);
    expect(colorOf(tester, '방 추가'), darkOnPrimaryContainer);
  });

  testWidgets('홈 — 연결 끊김 배너 글자가 다크 errorContainer 위 색이다', (tester) async {
    await pumpDark(
      tester,
      HomeScreen(
        events: const [],
        rooms: const [],
        loadingEvents: false,
        loadingRooms: false,
        connectionError: '서버와 연결이 끊겼습니다.',
        unreadCount: 0,
        onGoNotifications: () {},
        onGoSettings: () {},
        onChangeTab: (_) {},
        api: Api(),
        onLogout: () {},
      ),
    );

    expect(colorOf(tester, '서버와 연결이 끊겼습니다.'), const Color(0xFFFFB4A0));
  });
}
```

`Api()`를 그냥 쓴다. `HomeScreen`은 빌드 중 `api`의 메서드를 부르지 않고 타일을 눌렀을 때만 상세 화면에 넘긴다.

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/dark_mode_test.dart`

Expected: FAIL 2건. `Expected: Color(0xffe2e6e5) / Actual: Color(0xff191c1b)` — 지금은 라이트 상수가 그려진다.

- [ ] **Step 3: `Scaffold`·`AppBar` 세 줄 삭제**

`app/lib/screens/home.dart:46-52`를 이렇게 바꾼다. 47·49·50번 줄이 사라진다.

```dart
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('홈 화면', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
```

- [ ] **Step 4: 헬퍼 호출부에 `context` 넘기기**

`app/lib/screens/home.dart:70`:

```dart
          _addRoomCard(context),
```

`app/lib/screens/home.dart:73`:

```dart
            _connectionBanner(context),
```

- [ ] **Step 5: 빈 목록 안내와 제목 스타일 치환**

`app/lib/screens/home.dart:80-86` (`const Padding`에서 `const`가 빠진다):

```dart
          else if (unread.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '아직 감지된 낙상이 없습니다.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
```

`app/lib/screens/home.dart:100-101`:

```dart
  TextStyle _titleStyle(BuildContext context) => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      );
```

- [ ] **Step 6: `_addRoomCard`·`_connectionBanner` 교체**

`app/lib/screens/home.dart:103-165`의 두 메서드를 통째로 바꾼다.

```dart
  Widget _addRoomCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onChangeTab(1),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.grid_view, size: 32, color: scheme.onPrimaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '방 추가',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '방을 등록해 두세요.',
                      style: TextStyle(fontSize: 15, color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connectionError!,
              style: TextStyle(fontSize: 15, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
```

`Column(children: const [...])`가 `Column(children: [...])`이 된 것에 주의한다.

- [ ] **Step 7: `_alertCard`·`_alertTile` 교체**

`app/lib/screens/home.dart:167-232`의 두 메서드를 통째로 바꾼다. `AppColors.error`·`AppColors.primary`는 남는다.

```dart
  Widget _alertCard(BuildContext context, List<FallEvent> list, {required bool onlyFirst, required bool dimTitle}) {
    final items = onlyFirst ? list.take(1).toList() : list;
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _alertTile(context, items[i], dimTitle: dimTitle),
            if (i < items.length - 1)
              Divider(height: 1, indent: 16, endIndent: 16, color: outlineVariant),
          ],
        ],
      ),
    );
  }

  Widget _alertTile(BuildContext context, FallEvent e, {required bool dimTitle}) {
    final acknowledged = e.isAcknowledged;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(
        acknowledged ? Icons.check_circle : Icons.warning_amber,
        color: acknowledged ? scheme.onSurfaceVariant : AppColors.error,
      ),
      title: Text(
        e.roomLabel,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: dimTitle ? scheme.onSurfaceVariant : scheme.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(_fmt(e.occurredAt), style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
      ),
      // 우선순위: 119 신고됨 > 괜찮다고 말함 > 확인함/미확인 — 알림 확인 창과 같다
      trailing: e.isReported119
          ? const Text(
              '119 신고됨',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.error),
            )
          : e.isVoiceOk
              ? const Text(
                  '괜찮다고 말함',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary),
                )
              : Text(
                  acknowledged ? '확인함' : '미확인',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: acknowledged ? scheme.onSurfaceVariant : AppColors.error,
                  ),
                ),
      onTap: () async {
        await Navigator.of(context).push<FallEvent>(
          MaterialPageRoute(builder: (_) => FallDetailScreen(api: api, event: e)),
        );
        // 홈에서는 별도 갱신 로직 없음 — MainShell의 폴러가 다음 틱에 반영
      },
    );
  }
```

- [ ] **Step 8: 통과 확인**

Run: `cd app && flutter test && flutter analyze`

Expected: 기존 24 + 신규 5(과제 1) + 신규 2 = `+31: All tests passed!` / `No issues found!`

- [ ] **Step 9: 남은 참조 확인**

Run: `cd app && grep -o "AppColors\.[a-zA-Z]*" lib/screens/home.dart | sort | uniq -c`

Expected: `AppColors.error` 3건, `AppColors.primary` 1건. 그 외가 나오면 빠뜨린 것이다.

- [ ] **Step 10: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/screens/home.dart app/test/dark_mode_test.dart
git commit -m "fix: 홈 화면 색을 테마에서 읽도록 전환"
```

---

## Task 3: `settings.dart`(19곳) · `fall_list.dart`(15곳)

**Files:**
- Modify: `app/lib/screens/settings.dart`, `app/lib/screens/fall_list.dart`
- Test: `app/test/dark_mode_test.dart` (과제 2가 만든 파일에 추가)

**Interfaces:**
- Consumes: `buildAppTheme`, `pumpDark`·`colorOf`·`darkOnSurfaceVariant` (과제 2가 `dark_mode_test.dart`에 정의).
- Produces: 없음. 두 파일 다 `State` 클래스라 `context`가 이미 멤버로 있어 시그니처 변경이 없다.

- [ ] **Step 1: 실패하는 테스트 추가**

`app/test/dark_mode_test.dart`의 import에 두 줄을 더한다.

```dart
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_list.dart';
import 'package:fall_guardian/screens/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

파일 안에 가짜 Api와 이벤트를 더한다.

```dart
class FakeApi extends Api {
  @override
  Future<List<FallEvent>> listFalls() async => const [];
}

final sampleEvent = FallEvent(
  id: 1,
  roomName: '안방',
  roomNumber: 1,
  occurredAt: DateTime(2026, 7, 28, 4, 35),
  createdAt: DateTime(2026, 7, 28, 4, 35),
  confidence: 0.9,
);
```

`void main()` 맨 위에 `setUp`을 넣고, 테스트 두 개를 더한다.

```dart
  // SettingsScreen이 initState에서 LocalStore를 읽는다
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('설정 — 카드 제목이 다크 보조 글자색이다', (tester) async {
    await pumpDark(tester, const SettingsScreen());
    await tester.pump(); // _load()의 비동기 응답

    expect(colorOf(tester, '앱 설정'), darkOnSurfaceVariant);
    expect(colorOf(tester, 'MVP v1.0'), darkOnSurfaceVariant);
  });

  testWidgets('알림 목록 — 타일 시각이 다크 보조 글자색이다', (tester) async {
    await pumpDark(
      tester,
      FallListScreen(
        api: FakeApi(),
        events: [sampleEvent],
        loading: false,
        connectionError: null,
        onLogout: () {},
        onRefresh: () async {},
      ),
    );

    expect(colorOf(tester, '7월 28일 04:35'), darkOnSurfaceVariant);
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/dark_mode_test.dart`

Expected: FAIL 2건. `Expected: Color(0xffbfc9c6) / Actual: Color(0xff3f4947)`

- [ ] **Step 3: `settings.dart` 치환**

`app/lib/screens/settings.dart:68-72`에서 69·71·72번 줄을 삭제한다.

```dart
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
```

나머지는 줄 단위 치환이다. `const`가 사라지는 줄에 주의한다.

| 줄 | 지금 | 바꿀 것 |
|---|---|---|
| 95 | `Divider(height: 1, color: AppColors.outlineVariant, indent: 0, endIndent: 0),` | `Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant, indent: 0, endIndent: 0),` |
| 101 | `Divider(height: 1, color: AppColors.outlineVariant),` | `Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),` |
| 114 | `color: AppColors.errorContainer,` | `color: Theme.of(context).colorScheme.errorContainer,` |
| 119 | `const Icon(Icons.warning_amber, size: 18, color: AppColors.onErrorContainer),` | `Icon(Icons.warning_amber, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),` |
| 126 | `color: AppColors.onErrorContainer,` | `color: Theme.of(context).colorScheme.onErrorContainer,` |
| 141 | `trailing: const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),` | `trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),` |
| 144 | `const Divider(height: 1, color: AppColors.outlineVariant),` | `Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),` |
| 147 | `trailing: const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),` | `trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),` |
| 150 | `const Divider(height: 1, color: AppColors.outlineVariant),` | `Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),` |
| 168 | `border: Border.all(color: AppColors.outline),` | `border: Border.all(color: Theme.of(context).colorScheme.outline),` |
| 183 | `color: AppColors.primaryContainer,` | `color: Theme.of(context).colorScheme.primaryContainer,` |
| 195-196 | `? AppColors.onPrimaryContainer` / `: AppColors.onSurface,` | `? Theme.of(context).colorScheme.onPrimaryContainer` / `: Theme.of(context).colorScheme.onSurface,` |
| 203 | `const SizedBox(width: 1, child: SizedBox(height: 24, child: VerticalDivider(color: AppColors.outline))),` | `SizedBox(width: 1, child: SizedBox(height: 24, child: VerticalDivider(color: Theme.of(context).colorScheme.outline))),` |

153-156번 줄은 `const Text`에서 `const`가 빠진다.

```dart
                      trailing: Text(
                        'MVP v1.0',
                        style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
```

224-227번 줄도 마찬가지다.

```dart
              child: Text(
                heading,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
```

`import '../app_theme.dart';`는 남긴다 — `TextScale`을 계속 쓴다.

- [ ] **Step 4: `fall_list.dart` 치환**

`app/lib/screens/fall_list.dart:92-96`에서 93·95·96번 줄을 삭제한다.

```dart
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
```

| 줄 | 지금 | 바꿀 것 |
|---|---|---|
| 112 | `color: AppColors.errorContainer,` | `color: Theme.of(context).colorScheme.errorContainer,` |
| 115 | `child: Text(_error!, style: const TextStyle(color: AppColors.onErrorContainer)),` | `child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),` |
| 141 | `const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.outlineVariant),` | `Divider(height: 1, indent: 16, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant),` |

`_alertTile`(152-199)은 상단에 `scheme`을 뽑고 네 자리를 바꾼다.

```dart
  Widget _alertTile(FallEvent e) {
    final acknowledged = e.isAcknowledged;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(
        acknowledged ? Icons.check_circle : Icons.warning_amber,
        color: acknowledged ? scheme.onSurfaceVariant : AppColors.error,
      ),
      title: Text(
        e.roomLabel,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: acknowledged ? scheme.onSurfaceVariant : scheme.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(_fmt(e.occurredAt), style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
      ),
```

`trailing:`의 `const Text` 두 개(176·181번 줄, `AppColors.error`·`AppColors.primary`)는 `const`째로 그대로 두고, 마지막 분기(188번 줄)만 바꾼다.

```dart
              : Text(
                  acknowledged ? '확인함' : '미확인',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: acknowledged ? scheme.onSurfaceVariant : AppColors.error,
                  ),
                ),
```

- [ ] **Step 5: 통과 확인**

Run: `cd app && flutter test && flutter analyze`

Expected: `+33: All tests passed!` / `No issues found!`

- [ ] **Step 6: 남은 참조 확인**

Run: `cd app && grep -o "AppColors\.[a-zA-Z]*" lib/screens/settings.dart lib/screens/fall_list.dart | sort | uniq -c`

Expected: `fall_list.dart:AppColors.error` 3건, `fall_list.dart:AppColors.primary` 1건. `settings.dart`는 한 건도 안 나온다.

- [ ] **Step 7: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/screens/settings.dart app/lib/screens/fall_list.dart app/test/dark_mode_test.dart
git commit -m "fix: 설정·알림 목록 색을 테마에서 읽도록 전환"
```

---

## Task 4: `profile.dart` — 21곳 + 스펙에 없던 1곳

**Files:**
- Modify: `app/lib/screens/profile.dart`
- Test: `app/test/dark_mode_test.dart` (추가)

**Interfaces:**
- Consumes: `dangerColors(Brightness)` (과제 1), `pumpDark`·`colorOf`·`darkOnSurfaceVariant` (과제 2).
- Produces: 없음.

**이 파일에만 있는 것.** `profile.dart:170`의 `Border.all(color: AppColors.surface, width: 2)`는 카메라 배지를 두른 링이다. 페이지 배경을 오려낸 것처럼 보여야 하므로 `colorScheme.surface`가 아니라 **`Theme.of(context).scaffoldBackgroundColor`**로 간다. 다크에서 두 값이 다르다(`0xFF1B1F1E` vs `0xFF131716`). 라이트에서는 같아서 외관이 안 변한다. 스펙 §4 표에 없던 자리다.

- [ ] **Step 1: 실패하는 테스트 추가**

`app/test/dark_mode_test.dart`의 import에 한 줄을 더한다.

```dart
import 'package:fall_guardian/screens/profile.dart';
```

`FakeApi`에 `getProfile` 오버라이드를 더한다 — `ProfileScreen`이 `initState`에서 부른다.

```dart
class FakeApi extends Api {
  @override
  Future<List<FallEvent>> listFalls() async => const [];

  @override
  Future<Profile> getProfile() async => const Profile(elderPhone: '');
}
```

테스트를 더한다.

```dart
  testWidgets('프로필 — 카드 제목이 다크 보조 글자색, 탈퇴가 다크 danger 색이다', (tester) async {
    await pumpDark(
      tester,
      ProfileScreen(
        api: FakeApi(),
        unreadCount: 0,
        onGoNotifications: () {},
        onGoSettings: () {},
        onLogout: () {},
      ),
    );
    await tester.pump(); // _load()의 비동기 응답

    expect(colorOf(tester, '내 정보'), darkOnSurfaceVariant);
    expect(colorOf(tester, '회원 탈퇴'), const Color(0xFFFFB4A0));
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/dark_mode_test.dart`

Expected: FAIL. `Expected: Color(0xffbfc9c6) / Actual: Color(0xff3f4947)`

- [ ] **Step 3: `Scaffold`·`AppBar` 세 줄 삭제**

`app/lib/screens/profile.dart:69-74`에서 70·72·73번 줄을 삭제한다.

```dart
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('프로필', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
```

- [ ] **Step 4: 줄 단위 치환**

| 줄 | 지금 | 바꿀 것 |
|---|---|---|
| 104 | `style: const TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant),` | `style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),` |
| 136 | `textColor: AppColors.dangerFg),` | `textColor: dangerColors(Theme.of(context).brightness).fg),` |
| 200 | `color: AppColors.onSurfaceVariant,` | `color: Theme.of(context).colorScheme.onSurfaceVariant,` |
| 208 | `const Divider(height: 1, color: AppColors.outlineVariant),` | `Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),` |
| 235 | `color: textColor ?? AppColors.onSurface,` | `color: textColor ?? Theme.of(context).colorScheme.onSurface,` |
| 246 | `color: valueColor ?? AppColors.onSurfaceVariant,` | `color: valueColor ?? Theme.of(context).colorScheme.onSurfaceVariant,` |
| 253 | `color: textColor ?? AppColors.onSurfaceVariant,` | `color: textColor ?? Theme.of(context).colorScheme.onSurfaceVariant,` |
| 341 | `child: Text(subtitle, style: const TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant)),` | `child: Text(subtitle, style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant)),` |

124번 줄(`AppColors.error`), 168번 줄(`AppColors.primary`), 172번 줄(`AppColors.onPrimary`), 348번 줄(`AppColors.primary`)은 그대로 둔다.

195-202번 줄은 `const TextStyle`에서 `const`가 빠진다.

```dart
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
```

- [ ] **Step 5: `_avatar()` 교체 — 스펙에 없던 링 색**

`app/lib/screens/profile.dart:144-179`를 통째로 바꾼다.

```dart
  Widget _avatar() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, size: 44, color: scheme.onPrimaryContainer),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  // 링은 페이지 배경을 오려낸 것처럼 보여야 한다 — 다크에서
                  // scaffoldBackgroundColor와 colorScheme.surface가 서로 다르다
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 16, color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 6: 탈퇴 대화상자의 danger 색 교체**

`app/lib/screens/profile.dart:370-392`의 `showDialog` 안을 바꾼다. `builder`의 `context`가 바깥 `context`를 가리는데, 대화상자도 같은 테마를 물려받으므로 그대로 쓴다.

```dart
      builder: (context) {
        final tone = dangerColors(Theme.of(context).brightness);
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          title: const Text('회원 탈퇴', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          content: Text(
            '계정과 알림 기록이 모두 삭제되며 되돌릴 수 없습니다. 정말 탈퇴하시겠어요?',
            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: tone.bg,
                foregroundColor: tone.fg,
              ),
              child: const Text('탈퇴'),
            ),
          ],
        );
      },
```

`builder: (context) => AlertDialog(...)`가 `builder: (context) { ... return AlertDialog(...); }`로 바뀌는 것에 주의한다 — `tone`을 담을 지역 변수가 필요하다.

- [ ] **Step 7: 통과 확인**

Run: `cd app && flutter test && flutter analyze`

Expected: `+34: All tests passed!` / `No issues found!`

- [ ] **Step 8: 남은 참조 확인**

Run: `cd app && grep -o "AppColors\.[a-zA-Z]*" lib/screens/profile.dart | sort | uniq -c`

Expected: `AppColors.error` 1건, `AppColors.onPrimary` 1건, `AppColors.primary` 2건. 총 4건.

- [ ] **Step 9: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/screens/profile.dart app/test/dark_mode_test.dart
git commit -m "fix: 프로필 색을 테마에서 읽도록 전환 — 아바타 링은 페이지 배경색"
```

---

## Task 5: `fall_detail.dart` — 17곳 + 원시 리터럴 7곳

**Files:**
- Modify: `app/lib/screens/fall_detail.dart`
- Test: `app/test/dark_mode_test.dart` (추가)

**Interfaces:**
- Consumes: `dangerColors(Brightness)` (과제 1), `pumpDark`·`colorOf`·`FakeApi` (과제 2·3).
- Produces: 없음.

**이 화면이 실기기 스크린샷의 증상 그 자체다.** 비활성 "돌봄 대상자에게 전화" 버튼이 배경은 테마에서(`surfaceContainer` → 다크 `0xFF222625`), 글자색은 라이트 상수에서 받아 거의 안 보이는 조합이 된다. 326-329번 줄이다.

- [ ] **Step 1: 실패하는 테스트 추가**

`app/test/dark_mode_test.dart`의 import에 한 줄을 더한다.

```dart
import 'package:fall_guardian/screens/fall_detail.dart';
```

테스트를 더한다.

```dart
  testWidgets('낙상 상세 — 라벨이 다크 보조 글자색, 비활성 전화 버튼 글자가 다크 onSurface 계열이다', (tester) async {
    await pumpDark(tester, FallDetailScreen(api: FakeApi(), event: sampleEvent));
    await tester.pump(); // getProfile()의 비동기 응답

    expect(colorOf(tester, '발생 시각'), darkOnSurfaceVariant);

    // 전화번호 미등록이라 비활성이다 — 비활성 글자색이 다크 onSurface의 38%여야 한다
    final phoneButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('돌봄 대상자에게 전화'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(
      phoneButton.style?.foregroundColor?.resolve({WidgetState.disabled}),
      darkOnSurface.withValues(alpha: 0.38),
    );
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/dark_mode_test.dart`

Expected: FAIL. `Expected: Color(0xffbfc9c6) / Actual: Color(0xff3f4947)`

- [ ] **Step 3: `Scaffold`·`AppBar` 세 줄 삭제**

`app/lib/screens/fall_detail.dart:125-130`에서 126·128·129번 줄을 삭제한다.

```dart
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop(_event)),
```

- [ ] **Step 4: 본문 치환**

| 줄 | 지금 | 바꿀 것 |
|---|---|---|
| 156 | `valueColor: _event.isAcknowledged ? AppColors.onSurfaceVariant : AppColors.error,` | `valueColor: _event.isAcknowledged ? Theme.of(context).colorScheme.onSurfaceVariant : AppColors.error,` |
| 244 | `color: valueColor ?? AppColors.onSurface,` | `color: valueColor ?? Theme.of(context).colorScheme.onSurface,` |

149·162번 줄(`AppColors.primary`)은 그대로 둔다.

188-192번 줄은 `const Text`에서 `const`가 빠진다.

```dart
            Text(
              '프로필에서 전화번호를 등록하면 켜집니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
```

233-236번 줄도 마찬가지다.

```dart
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
```

- [ ] **Step 5: `_actionButton` 교체 — 원시 리터럴 7곳이 여기 있다**

`app/lib/screens/fall_detail.dart:253-335`를 통째로 바꾼다. `bool danger` 매개변수와 이름이 겹치지 않게 지역 변수를 `tone`으로 둔다.

```dart
  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required bool filled,
    bool outlinedWithSurface = false,
    bool emergency = false,
    bool danger = false,
    VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 원래 상수 Color(0x1F191C1B) · Color(0x61191C1B)는 라이트 onSurface에
    // Material 비활성 알파(배경 12% · 전경 38%)를 씌운 값이다. 의미를 그대로 두고 밝기만 따라가게 한다.
    final disabledBg = scheme.onSurface.withValues(alpha: 0.12);
    final disabledFg = scheme.onSurface.withValues(alpha: 0.38);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final inner = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ],
    );

    if (filled) {
      return SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: disabledBg,
            disabledForegroundColor: disabledFg,
            shape: shape,
          ),
          child: inner,
        ),
      );
    }
    if (emergency) {
      return SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: disabledBg,
            disabledForegroundColor: disabledFg,
            shape: shape,
          ),
          child: inner,
        ),
      );
    }
    if (danger) {
      final tone = dangerColors(Theme.of(context).brightness);
      return SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: tone.bg,
            foregroundColor: tone.fg,
            disabledBackgroundColor: tone.bg.withValues(alpha: 0.4),
            disabledForegroundColor: tone.fg.withValues(alpha: 0.38),
            shape: shape,
          ),
          child: inner,
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: outlinedWithSurface ? scheme.surfaceContainer : null,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          disabledForegroundColor: disabledFg,
          shape: shape,
        ),
        child: inner,
      ),
    );
  }
```

- [ ] **Step 6: 통과 확인**

Run: `cd app && flutter test && flutter analyze`

Expected: `+35: All tests passed!` / `No issues found!`

- [ ] **Step 7: 남은 참조 확인**

Run: `cd app && grep -o "AppColors\.[a-zA-Z]*\|Color(0x[0-9A-Fa-f]*)" lib/screens/fall_detail.dart | sort | uniq -c`

Expected: `AppColors.error` 2건, `AppColors.onPrimary` 1건, `AppColors.primary` 3건. `Color(0x…)`는 한 건도 안 나온다.

- [ ] **Step 8: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/screens/fall_detail.dart app/test/dark_mode_test.dart
git commit -m "fix: 낙상 상세 색을 테마에서 읽도록 전환 — 비활성 색은 onSurface 알파로"
```

---

## Task 6: `room_management.dart`(15) · `start.dart`(7) · `login.dart`(13+3) · `signup.dart`(13+2)

**Files:**
- Modify: `app/lib/screens/room_management.dart`, `app/lib/screens/start.dart`, `app/lib/screens/login.dart`, `app/lib/screens/signup.dart`
- Test: `app/test/dark_mode_test.dart` (추가)

**Interfaces:**
- Consumes: `dangerColors(Brightness)` (과제 1), `pumpDark`·`colorOf`·`darkOnSurfaceVariant` (과제 2).
- Produces: 없음. 네 파일 모두 시그니처 변경이 없다.

- [ ] **Step 1: 실패하는 테스트 추가**

`app/test/dark_mode_test.dart`의 import에 두 줄을 더한다.

```dart
import 'package:fall_guardian/screens/room_management.dart';
import 'package:fall_guardian/screens/start.dart';
```

테스트를 더한다.

```dart
  testWidgets('방 관리 — 안내 문구가 다크 보조 글자색이다', (tester) async {
    await pumpDark(
      tester,
      RoomManagementScreen(
        api: FakeApi(),
        rooms: const [],
        loading: false,
        reload: () async {},
        unreadCount: 0,
        onGoNotifications: () {},
        onGoSettings: () {},
      ),
    );

    expect(colorOf(tester, '방을 등록하면, 낙상 알림이 어디에서 일어났는지 표시됩니다.'), darkOnSurfaceVariant);
  });

  testWidgets('시작 화면 — 제목과 소개가 다크 글자색이다', (tester) async {
    await pumpDark(tester, StartScreen(api: FakeApi()));

    expect(colorOf(tester, '낙상 알림'), darkOnSurface);
    expect(
      colorOf(tester, '돌봄 대상자의 낙상을 감지해\n보호자에게 실시간으로 알려드립니다.'),
      darkOnSurfaceVariant,
    );
  });
```

`login.dart`·`signup.dart`는 바뀌는 자리가 입력칸 힌트와 비활성 버튼 색이라 `colorOf`로 잡히지 않는다. 이 둘은 Step 6의 grep 검증으로 확인한다.

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/dark_mode_test.dart`

Expected: FAIL 2건. `Expected: Color(0xffbfc9c6) / Actual: Color(0xff3f4947)`

- [ ] **Step 3: `room_management.dart` 치환**

`app/lib/screens/room_management.dart:36-41`에서 37·39·40번 줄을 삭제한다.

```dart
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('방 관리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
```

62-65번 줄은 `const Text`에서 `const`가 빠진다.

```dart
                Text(
                  '방을 등록하면, 낙상 알림이 어디에서 일어났는지 표시됩니다.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: -0.01,
                  ),
                ),
```

| 줄 | 지금 | 바꿀 것 |
|---|---|---|
| 99 | `color: AppColors.primaryContainer,` | `color: Theme.of(context).colorScheme.primaryContainer,` |
| 104 | `style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onPrimaryContainer),` | `style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onPrimaryContainer),` |
| 149 | `border: Border.all(color: AppColors.outline, style: BorderStyle.solid),` | `border: Border.all(color: Theme.of(context).colorScheme.outline, style: BorderStyle.solid),` |

113-116번 줄은 `const Text`에서 `const`가 빠진다.

```dart
          Text(
            '기기 연결',
            style: TextStyle(fontSize: 15, height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
```

152-162번 줄의 `const Column`은 `AppColors.primary`만 쓰므로 `const`째로 그대로 둔다. 187·196번 줄(`AppColors.primary`)도 그대로다.

`_deleteRoom`(228-261)의 대화상자를 바꾼다. 여기도 `builder`가 블록 본문이 된다.

```dart
      builder: (context) {
        final tone = dangerColors(Theme.of(context).brightness);
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          title: Text(
            '${room.name} 삭제',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '이미 기록된 낙상 이력은 지워지지 않습니다. 이 방에 연결된 기기도 해제됩니다.',
            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: tone.bg,
                foregroundColor: tone.fg,
              ),
              child: const Text('삭제'),
            ),
          ],
        );
      },
```

- [ ] **Step 4: `start.dart` 치환**

`app/lib/screens/start.dart:18-20`에서 19번 줄을 삭제한다.

```dart
    return Scaffold(
      body: SafeArea(
```

29-45번 줄에서 `const Text` 두 개의 `const`가 빠진다.

```dart
              Text(
                '낙상 알림',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  letterSpacing: -0.02,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '돌봄 대상자의 낙상을 감지해\n보호자에게 실시간으로 알려드립니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
```

72번 줄만 더 바꾼다. 55·56·71번 줄(`primary`·`onPrimary`)은 그대로다.

```dart
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
```

- [ ] **Step 5: `login.dart`·`signup.dart` 치환**

`app/lib/screens/login.dart:55-65`에서 56·63·64번 줄을 삭제한다.

```dart
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('로그인'),
      ),
```

`app/lib/screens/signup.dart:61-71`에서 62·69·70번 줄을 같은 방식으로 삭제한다.

원시 리터럴 5곳과 나머지를 바꾼다. 두 파일의 `_buildField`는 내용이 같다.

| 파일:줄 | 지금 | 바꿀 것 |
|---|---|---|
| `login.dart:84` | `disabledBackgroundColor: const Color(0x1F191C1B),` | `disabledBackgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),` |
| `login.dart:85` | `disabledForegroundColor: const Color(0x61191C1B),` | `disabledForegroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),` |
| `login.dart:109` | `color: _busy ? const Color(0x61191C1B) : AppColors.primary,` | `color: _busy ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38) : AppColors.primary,` |
| `signup.dart:103` | `disabledBackgroundColor: const Color(0x1F191C1B),` | `disabledBackgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),` |
| `signup.dart:104` | `disabledForegroundColor: const Color(0x61191C1B),` | `disabledForegroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),` |

`signup.dart:80-88`은 `const Text`에서 `const`가 빠진다.

```dart
              Text(
                '비밀번호는 영문자, 숫자, 특수기호를 섞어 8자 이상으로 만들어주세요.',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  letterSpacing: -0.02,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
```

두 파일의 `_buildField`에서 같은 네 줄을 바꾼다(`login.dart:138·141·144·148`, `signup.dart:142·145·148·152`).

```dart
        style: TextStyle(fontSize: 17, height: 1.3, color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(fontSize: 17, color: Theme.of(context).colorScheme.outline),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
```

`focusedBorder`의 `AppColors.primary`(`login.dart:152`, `signup.dart:156`)는 `const`째로 그대로 둔다.

- [ ] **Step 6: 통과 확인과 남은 참조 확인**

Run: `cd app && flutter test && flutter analyze`

Expected: `+37: All tests passed!` / `No issues found!`

Run: `cd app && grep -ho "AppColors\.[a-zA-Z]*\|Color(0x[0-9A-Fa-f]*)" lib/screens/room_management.dart lib/screens/start.dart lib/screens/login.dart lib/screens/signup.dart | sort | uniq -c`

Expected: `AppColors.error` 2, `AppColors.onPrimary` 5, `AppColors.primary` 11. `Color(0x…)`는 한 건도 안 나온다.

파일별 내역은 `room_management` primary 4 / `start` onPrimary 1 · primary 2 / `login` error 1 · onPrimary 2 · primary 3 / `signup` error 1 · onPrimary 2 · primary 2다.

- [ ] **Step 7: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/screens/room_management.dart app/lib/screens/start.dart \
        app/lib/screens/login.dart app/lib/screens/signup.dart app/test/dark_mode_test.dart
git commit -m "fix: 방 관리·시작·로그인·회원가입 색을 테마에서 읽도록 전환"
```

---

## Task 7: `fall_alert_dialog.dart` — 사고 발생 창

**Files:**
- Create: `app/lib/screens/fall_alert_dialog.dart`
- Test: `app/test/fall_alert_dialog_test.dart` (신규)

**Interfaces:**
- Consumes: `FallEvent` (`app/lib/models.dart` — `roomName`·`roomNumber`·`occurredAt`), `AppColors.primary`·`onPrimary`.
- Produces: `class FallAlertDialog extends StatelessWidget` — 생성자는 `const FallAlertDialog({super.key, required FallEvent event})`. 과제 8이 `showDialog`의 `builder`에서 쓴다.

**창은 `showDialog`로 띄우는 것을 전제로 만든다.** `barrierDismissible: false`는 부르는 쪽(과제 8)이 주고, 이 위젯은 `PopScope(canPop: false)`로 뒤로가기·스와이프를 막는다. 둘이 합쳐져야 "확인이 유일한 출구"가 된다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/fall_alert_dialog_test.dart`를 새로 만든다.

```dart
// 사고 발생 창 — 방·시각 표시와 "확인이 유일한 출구"인지

import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _event = FallEvent(
  id: 1,
  roomName: '안방',
  roomNumber: 2,
  occurredAt: DateTime(2026, 7, 28, 4, 35),
  createdAt: DateTime(2026, 7, 28, 4, 35),
  confidence: 0.9,
);

Future<void> _open(WidgetTester tester, {bool dark = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(dark: dark, scale: TextScale.normal),
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) => FallAlertDialog(event: _event),
        ),
        child: const Text('열기'),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('방 이름·방 번호·발생 시각이 창에 뜬다', (tester) async {
    await _open(tester);

    expect(find.text('사고 발생'), findsOneWidget);
    expect(find.text('안방'), findsOneWidget);
    expect(find.text('2번'), findsOneWidget);
    expect(find.text('7월 28일 04:35'), findsOneWidget);
  });

  testWidgets('확인을 누르면 닫힌다', (tester) async {
    await _open(tester);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('사고 발생'), findsNothing);
  });

  testWidgets('바깥을 탭해도 안 닫힌다', (tester) async {
    await _open(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('사고 발생'), findsOneWidget);
  });

  testWidgets('시스템 뒤로가기로도 안 닫힌다', (tester) async {
    await _open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('사고 발생'), findsOneWidget);
  });

  testWidgets('다크 테마에서도 오버플로 없이 그려진다', (tester) async {
    await _open(tester, dark: true);

    expect(find.text('사고 발생'), findsOneWidget);
  });
}
```

마지막 테스트가 그냥 통과만 보는 것처럼 보이지만, Flutter 위젯 테스트는 레이아웃 오버플로를 예외로 던지므로 `findsOneWidget`에 닿았다는 것 자체가 오버플로가 없다는 뜻이다.

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/fall_alert_dialog_test.dart`

Expected: FAIL. 컴파일 단계에서 `Error: Error when reading 'lib/screens/fall_alert_dialog.dart': No such file or directory` — 아직 파일이 없다.

- [ ] **Step 3: 창 위젯 구현**

`app/lib/screens/fall_alert_dialog.dart`를 새로 만든다.

```dart
// 낙상 발생 알림 창 — 방·시각을 보여주고 확인 버튼으로만 닫힌다

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

class FallAlertDialog extends StatelessWidget {
  const FallAlertDialog({super.key, required this.event});

  final FallEvent event;

  // 홈·알림 목록과 같은 형식이다
  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // 뒤로가기·스와이프로 닫히지 않는다. 부르는 쪽의 barrierDismissible: false와
      // 합쳐져 확인 버튼이 유일한 출구가 된다.
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, size: 40, color: scheme.error),
        title: const Text('사고 발생', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(context, '방 이름', event.roomName),
            _row(context, '방 번호', '${event.roomNumber}번'),
            _row(context, '발생 시각', _fmt(event.occurredAt)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              child: const Text('확인'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
```

창 배경은 지정하지 않는다 — 테마의 `surfaceContainerHigh`로 떨어지고 그 값은 과제 1에서 이미 밝기별로 분기돼 있다.

- [ ] **Step 4: 통과 확인**

Run: `cd app && flutter test test/fall_alert_dialog_test.dart && flutter analyze`

Expected: `+5: All tests passed!` / `No issues found!`

- [ ] **Step 5: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/screens/fall_alert_dialog.dart app/test/fall_alert_dialog_test.dart
git commit -m "feat: 사고 발생 창 — 방·시각 표시와 확인 버튼 단일 출구"
```

---

## Task 8: `main_shell.dart` — 대기열과 순차 표시

**Files:**
- Modify: `app/lib/screens/main_shell.dart`
- Test: `app/test/main_shell_alert_test.dart` (신규)

**Interfaces:**
- Consumes: `FallAlertDialog({required FallEvent event})` (과제 7), `FallPoller.onEvents(List<FallEvent> all, List<FallEvent> fresh, List<FallEvent> newlyOk)` (`app/lib/poller.dart` — 기존).
- Produces: 없음. 추가되는 `_alertQueue`·`_alertShowing`·`_queueAlerts`·`_drainAlerts`는 전부 `_MainShellState`의 private 멤버다.

**함정 두 개를 먼저 읽는다.**

1. **테스트에 `SharedPreferences.setMockInitialValues`가 반드시 필요하다.** `onEvents`는 `fresh`마다 `await Notifications.show(e)`를 부르고, 그 안이 `LocalStore.notificationsOn()` → `SharedPreferences.getInstance()`다. mock이 없으면 이 `await`가 안 풀려서 `_queueAlerts`에 영영 도달하지 않는다. **예외도 로그도 안 남고** 그냥 창이 안 뜬다(실측: `Found 0 widgets`). 알림을 꺼 두면 `show()`가 플러그인 채널 전에 돌아온다.
2. **`import 'dart:async';`가 필요하다.** `unawaited`가 거기 있다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/main_shell_alert_test.dart`를 새로 만든다.

```dart
// 새 낙상이 오면 사고 발생 창이 순차로 뜨는지 — 안 띄워야 하는 경우까지

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 폴링 호출마다 다음 응답을 준다. 목록이 떨어지면 마지막 응답을 계속 반복한다.
class _FakeApi extends Api {
  _FakeApi(this.responses);

  final List<List<FallEvent>> responses;
  int _calls = 0;
  final ackIds = <int>[];

  @override
  Future<List<FallEvent>> listFalls() async {
    final i = _calls < responses.length ? _calls : responses.length - 1;
    _calls++;
    return responses[i];
  }

  @override
  Future<List<Room>> listRooms() async => const [];

  @override
  Future<FallEvent> acknowledge(int id) async {
    ackIds.add(id);
    return responses.last.firstWhere((e) => e.id == id);
  }
}

FallEvent _event(int id, {DateTime? voiceOkAt}) => FallEvent(
      id: id,
      roomName: '안방',
      roomNumber: id,
      occurredAt: DateTime(2026, 7, 28, 4, 35),
      createdAt: DateTime(2026, 7, 28, 4, 35),
      confidence: 0.9,
      voiceOkAt: voiceOkAt,
    );

Future<void> _pumpShell(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(MaterialApp(home: MainShell(api: api)));
  await tester.pump(); // 첫 폴링(프라이밍) 응답
}

// 폴러의 5초 주기를 한 번 굴리고, 다이얼로그 전환이 끝날 때까지 프레임을 소화한다
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    // Notifications.show가 SharedPreferences를 먼저 읽는다 — 알림을 꺼 두면
    // 플러그인 채널까지 가지 않고 바로 돌아온다. 이 줄이 없으면 창이 영영 안 뜬다.
    SharedPreferences.setMockInitialValues({'local.notifications_on': false});
  });

  testWidgets('새 낙상 2건이면 확인을 두 번 눌러야 둘 다 사라진다', (tester) async {
    final api = _FakeApi([
      const [],
      [_event(2), _event(1)], // 서버는 최신순으로 준다
    ]);
    await _pumpShell(tester, api);
    expect(find.text('사고 발생'), findsNothing);

    await _tick(tester);

    // 최신 낙상부터 뜬다
    expect(find.text('사고 발생'), findsOneWidget);
    expect(find.text('2번'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('사고 발생'), findsOneWidget);
    expect(find.text('1번'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('사고 발생'), findsNothing);
  });

  testWidgets('로그인 직후 최초 응답의 기존 낙상으로는 창이 안 뜬다', (tester) async {
    final api = _FakeApi([
      [_event(1)],
    ]);
    await _pumpShell(tester, api);

    expect(find.text('사고 발생'), findsNothing);
    await _tick(tester);
    expect(find.text('사고 발생'), findsNothing);
  });

  testWidgets('newlyOk(뒤늦은 괜찮음 응답)로는 창이 안 뜬다', (tester) async {
    final api = _FakeApi([
      [_event(1)],
      [_event(1, voiceOkAt: DateTime(2026, 7, 28, 4, 35, 12))],
    ]);
    await _pumpShell(tester, api);

    await _tick(tester);

    expect(find.text('사고 발생'), findsNothing);
  });

  testWidgets('확인을 눌러도 서버에 확인 기록 요청이 나가지 않는다', (tester) async {
    final api = _FakeApi([
      const [],
      [_event(1)],
    ]);
    await _pumpShell(tester, api);
    await _tick(tester);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(api.ackIds, isEmpty);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/main_shell_alert_test.dart`

Expected: FAIL 2건 (`새 낙상 2건…`, `확인을 눌러도…`). `Expected: exactly one matching candidate / Actual: Found 0 widgets with text "사고 발생"`. 나머지 2건은 "안 뜬다"를 보는 것이라 지금도 통과한다.

- [ ] **Step 3: import 추가**

`app/lib/screens/main_shell.dart`의 import 블록을 바꾼다. `dart:async`가 들어오고 `../app_theme.dart`가 빠지며(Step 6에서 마지막 참조가 사라진다) `fall_alert_dialog.dart`가 들어온다.

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../poller.dart';
import 'fall_alert_dialog.dart';
import 'fall_list.dart';
import 'home.dart';
import 'login.dart';
import 'profile.dart';
import 'room_management.dart';
import 'settings.dart';
```

- [ ] **Step 4: 상태 필드 추가**

`app/lib/screens/main_shell.dart:35`의 `late final FallPoller _poller;` 다음 줄에 붙인다.

```dart
  // 사고 발생 창 대기열 — 한 번에 하나만 띄우고 확인할 때마다 다음 것을 띄운다
  final _alertQueue = <FallEvent>[];
  bool _alertShowing = false;
```

- [ ] **Step 5: `onEvents`에 호출 추가**

`app/lib/screens/main_shell.dart:49-55`의 `setState` 블록 끝에 한 줄을 더한다.

```dart
        if (!mounted) return;
        setState(() {
          _events = all;
          _loadingEvents = false;
          _connectionError = null;
        });
        _queueAlerts(fresh);
```

`newlyOk`는 넘기지 않는다. 그것은 새 사고가 아니라 이미 알린 낙상에 괜찮음 응답이 뒤늦게 붙은 전이다.

- [ ] **Step 6: 대기열 메서드 추가**

`app/lib/screens/main_shell.dart`의 `dispose()` 다음, `_loadRooms()` 앞에 넣는다.

```dart
  void _queueAlerts(List<FallEvent> fresh) {
    if (fresh.isEmpty) return;
    // fresh는 서버가 준 최신순 목록에서 id로 거른 것이라 이미 최신순이다 — 최신 낙상부터 뜬다
    _alertQueue.addAll(fresh);
    if (!_alertShowing) unawaited(_drainAlerts());
  }

  // 폴러는 onEvents를 await하지 않고 부르므로(poller.dart:100) 창이 떠 있는 동안에도
  // 5초 폴링은 계속 돈다. 그 사이 도착한 새 낙상은 큐에 쌓였다가 이어서 뜬다.
  Future<void> _drainAlerts() async {
    _alertShowing = true;
    while (_alertQueue.isNotEmpty && mounted) {
      final event = _alertQueue.removeAt(0);
      await showDialog<void>(
        context: context,
        barrierDismissible: false, // 바깥을 눌러도 안 닫힌다
        useRootNavigator: true, // 설정·상세처럼 위에 쌓인 화면도 덮는다
        builder: (_) => FallAlertDialog(event: event),
      );
    }
    _alertShowing = false;
  }
```

`app/lib/screens/main_shell.dart:188`의 마지막 `AppColors` 참조도 바꾼다.

```dart
        indicatorColor: Theme.of(context).colorScheme.primaryContainer,
```

- [ ] **Step 7: 통과 확인**

Run: `cd app && flutter test && flutter analyze`

Expected: `+46: All tests passed!` / `No issues found!`

`unused_import`가 뜨면 Step 3에서 `../app_theme.dart`를 안 지운 것이다.

- [ ] **Step 8: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/screens/main_shell.dart app/test/main_shell_alert_test.dart
git commit -m "feat: 새 낙상마다 사고 발생 창을 순차로 띄운다"
```

---

## Task 9: 전체 검증 · 실기기 · 문서

**Files:**
- Modify: `app/lib/app_theme.dart` (죽은 상수 정리), `checklist.md`, `context-notes.md`
- Test: 전체 스위트

**Interfaces:**
- Consumes: 과제 1~8의 결과 전부.
- Produces: 없음.

- [ ] **Step 1: 남은 하드코딩 전수 확인**

Run:

```bash
cd /Users/munhokang/82107/weniv_project/app
echo "=== 남은 AppColors (splash 제외) ===" && \
grep -rn "AppColors\." lib --include='*.dart' | grep -v "splash.dart" | grep -v "app_theme.dart" | \
  grep -o "AppColors\.[a-zA-Z]*" | sort | uniq -c
echo "=== 남은 원시 리터럴 (splash 제외) ===" && \
grep -rn "Color(0x" lib/screens --include='*.dart' | grep -v "splash.dart"
echo "=== 남은 배경·앱바 지정 ===" && \
grep -rn "backgroundColor: AppColors\|foregroundColor: AppColors" lib --include='*.dart'
```

Expected:
- 첫 블록: `AppColors.error` 11, `AppColors.onPrimary` 8, `AppColors.primary` 19. **총 38건이고 다른 이름은 하나도 없다.** 전환 전 145건에서 삭제 25 + 치환 84를 뺀 36건이 남고, 여기에 `fall_alert_dialog.dart`가 새로 쓰는 `primary`·`onPrimary` 각 1건이 더해진 값이다.
- 둘째·셋째 블록: **아무것도 안 나온다.**

`onSurface`·`onSurfaceVariant`·`outline`·`outlineVariant`·`surface`·`primaryContainer`·`onPrimaryContainer`·`errorContainer`·`onErrorContainer`·`dangerBg`·`dangerFg` 중 하나라도 나오면 빠뜨린 치환이 있다.

- [ ] **Step 2: 파일별 잔여 참조 대조**

Run:

```bash
cd /Users/munhokang/82107/weniv_project/app
for f in lib/screens/*.dart lib/*.dart; do
  n=$(grep -o "AppColors\.[a-zA-Z]*" "$f" 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" != "0" ] && echo "$n	$f"
done | sort -rn
```

Expected — 이 표와 정확히 일치해야 한다.

| 건수 | 파일 | 남는 이름 |
|---|---|---|
| 18 | `lib/app_theme.dart` | 정의부(자기 참조) |
| 4 | `lib/screens/fall_list.dart` | error 3, primary 1 |
| 4 | `lib/screens/home.dart` | error 3, primary 1 |
| 4 | `lib/screens/profile.dart` | error 1, onPrimary 1, primary 2 |
| 4 | `lib/screens/splash.dart` | 손대지 않음 |
| 6 | `lib/screens/login.dart` | error 1, onPrimary 2, primary 3 |
| 5 | `lib/screens/signup.dart` | error 1, onPrimary 2, primary 2 |
| 6 | `lib/screens/fall_detail.dart` | error 2, onPrimary 1, primary 3 |
| 4 | `lib/screens/room_management.dart` | primary 4 |
| 3 | `lib/screens/start.dart` | onPrimary 1, primary 2 |
| 2 | `lib/screens/fall_alert_dialog.dart` | onPrimary 1, primary 1 |

`lib/screens/settings.dart`와 `lib/screens/main_shell.dart`는 목록에 **안 나와야** 한다.

수치가 다르면 그 파일에서 빠뜨린 치환이 있다. 해당 과제로 돌아가 고친다.

- [ ] **Step 3: 죽은 상수 정리**

과제 4·5·6이 `AppColors.dangerBg`·`dangerFg`의 마지막 참조를 걷어냈다. `app_theme.dart`의 정의만 남았으므로 지운다. `app/lib/app_theme.dart:26-28`의 세 줄을 삭제한다.

```dart
  // 파괴적 동작 — 톤 낮춘 tonal
  static const dangerBg = Color(0xFFF7DAD2);
  static const dangerFg = Color(0xFFA03920);
```

`pageBg`·`inverseSurface`는 **지우지 않는다.** 이번 작업이 만든 고아가 아니라 원래부터 안 쓰이던 상수다.

Run: `cd app && grep -rn "dangerBg\|dangerFg" lib test --include='*.dart'`

Expected: 아무것도 안 나온다.

- [ ] **Step 4: 전체 스위트와 정적 분석**

Run: `cd app && flutter test && flutter analyze`

Expected: `+46: All tests passed!` / `No issues found!`

내역은 기존 24 + `app_theme_test.dart` 5 + `dark_mode_test.dart` 8(과제 2가 2, 3이 2, 4가 1, 5가 1, 6이 2) + `fall_alert_dialog_test.dart` 5 + `main_shell_alert_test.dart` 4 = 46이다.

- [ ] **Step 5: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add app/lib/app_theme.dart
git commit -m "refactor: 마지막 참조가 사라진 dangerBg·dangerFg 상수 제거"
```

- [ ] **Step 6: 실기기 재빌드·재설치**

`.claude/skills/running-fall-guardian`을 따른다. `API_HOST`는 컴파일 타임에 박히므로 핫스팟이 재접속됐으면 주소부터 다시 잡는다.

```bash
cd /Users/munhokang/82107/weniv_project/app
xcrun devicectl list devices          # Identifier 열을 복사한다 (아래 $DEV)
HOST=$(ipconfig getifaddr en0)
[ -z "$HOST" ] && HOST="[$(ifconfig en0 | awk '/inet6 2/ && !/temporary/ && !/clat46/ {print $2; exit}')]"
echo "$HOST"                          # 비었거나 "[]"면 여기서 멈춘다
flutter build ios --release --dart-define=API_HOST="$HOST"
xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device $DEV com.example.fallGuardian
```

기기 ID가 두 종류다. `flutter devices`의 하드웨어 UDID(`00008140-…`)와 `devicectl`의 CoreDevice UUID(`529A6455-…`)는 바꿔 쓸 수 없다. 서명 미신뢰 에러는 대개 일시적이라 한 번 재시도해 본다.

- [ ] **Step 7: 실기기 수동 확인**

사람이 밟는다. 다음을 눈으로 본다.

1. 설정에서 다크모드를 켠다. 홈·방 관리·프로필·알림 목록·낙상 상세·설정·시작·로그인·회원가입에서 **페이지 배경이 어둡고 그 위 글자가 읽힌다.**
2. 홈의 "확인하지 않은 알림"·"최근 확인한 알림" 제목이 보인다(배경만 고쳤을 때 사라지던 자리다).
3. 낙상 상세에서 전화번호 미등록 상태의 "돌봄 대상자에게 전화" 버튼 글자가 읽힌다(첫 스크린샷의 증상 자리다).
4. 다크모드를 끄면 **외관이 전과 같다.**
5. 감지 페이지로 낙상을 만들면 앱 화면 한가운데 "사고 발생" 창이 뜨고, 방 이름·방 번호·발생 시각이 맞고, 바깥을 눌러도 안 닫히고 "확인"으로만 닫힌다.
6. 설정 화면을 열어 둔 채 낙상을 만들어도 그 위에 창이 뜬다.

- [ ] **Step 8: 문서 갱신과 커밋**

`checklist.md`에 23절을 더한다(22절 다음).

```markdown
## 23. 다크모드 색 정리 + 낙상 발생 모달 (2026-07-28)

설계: [docs/superpowers/specs/2026-07-28-dark-mode-fall-alert-design.md](docs/superpowers/specs/2026-07-28-dark-mode-fall-alert-design.md) / 계획: [docs/superpowers/plans/2026-07-28-dark-mode-fall-alert.md](docs/superpowers/plans/2026-07-28-dark-mode-fall-alert.md)

- [ ] app_theme 다크 팔레트 5색 + dangerColors (+테스트 5)
- [ ] 홈 24곳 — 헬퍼 2개에 context 추가
- [ ] 설정 19곳 · 알림 목록 15곳
- [ ] 프로필 21곳 — 아바타 링은 scaffoldBackgroundColor(스펙에 없던 자리)
- [ ] 낙상 상세 17곳 + 원시 리터럴 7곳
- [ ] 방 관리 15 · 시작 7 · 로그인 13 · 회원가입 13 (+원시 리터럴 5)
- [ ] 사고 발생 창 신규 (+테스트 5)
- [ ] MainShell 대기열·순차 표시 (+테스트 4)
- [ ] 검증 — flutter test 46개, flutter analyze 무경고, 죽은 상수 정리
- [ ] 수동 검증 — 실기기 다크모드 토글 + 실제 낙상으로 창 확인 (사람이 밟는다)
```

`context-notes.md` 끝에 이번 라운드의 결정을 덧붙인다. 최소한 다음 네 가지를 남긴다.

- 배경만 고치면 왜 더 나빠지는가(`home.dart`의 섹션 제목이 카드 밖 배경 위에 있다).
- `Scaffold`·`AppBar`는 치환이 아니라 삭제인 이유(테마에 이미 값이 있다).
- 아바타 링이 `colorScheme.surface`가 아니라 `scaffoldBackgroundColor`인 이유(다크에서 두 값이 다르다).
- `MainShell` 테스트에 `SharedPreferences.setMockInitialValues`가 없으면 예외 없이 창이 안 뜬다는 것(스펙이 경고한 pending timer는 실제로는 안 났다).

```bash
cd /Users/munhokang/82107/weniv_project
git add checklist.md context-notes.md
git commit -m "docs: 다크모드·사고 발생 창 라운드 체크리스트·컨텍스트 노트"
```

- [ ] **Step 9: main에 머지**

수동 검증까지 끝난 뒤에만 한다.

```bash
cd /Users/munhokang/82107/weniv_project
git checkout main
git merge --no-ff dark-mode-fall-alert
```
