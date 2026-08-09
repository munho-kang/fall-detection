# 사고 발생 창 전화·119 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사고 발생 창(`fall_alert_dialog.dart`)에 알림 상세 화면과 같은 "돌봄 대상자에게 전화"·"119 긴급 신고" 버튼을 넣는다.

**Architecture:** 발신 로직과 119 번호를 `lib/dial.dart`로 공용화한 뒤(상세 화면도 이걸 쓰게 정리), 창을 StatefulWidget으로 바꿔 `Api`를 주입받아 열릴 때 `getProfile()`로 어르신 번호를 조회한다. 전화를 걸어도 창은 유지되고 확인 버튼만이 유일한 출구다.

**Tech Stack:** Flutter (앱은 `app/`), url_launcher ^6.3.2, flutter_test 위젯 테스트.

**Spec:** `docs/superpowers/specs/2026-08-09-fall-alert-dialog-actions-design.md`

## Global Constraints

- 모든 명령은 `app/` 디렉터리에서 실행한다.
- 주석·문구는 한국어. 사용자 노출 문구는 스펙 그대로: "돌봄 대상자에게 전화", "119 긴급 신고", "프로필에서 전화번호를 등록하면 켜집니다.", "응답이 없어 119에 자동 신고되었습니다", "전화 앱을 열 수 없습니다."
- 119 번호는 시연용 상수 `01000000119` — `lib/dial.dart` 한 곳에만 존재해야 한다.
- 버튼 수치는 상세 화면 `_actionButton` 미러링: 높이 48 · 라운드 16 · 아이콘 20 · 글자 17/w700.
- 창의 기존 계약 불변: PopScope `canPop: false` + `barrierDismissible: false`, 확인 버튼만이 출구. 전화·119 버튼은 창을 닫지 않는다.
- 각 태스크 끝에서 `flutter analyze`와 `flutter test`가 깨끗해야 커밋한다.

---

### Task 1: `lib/dial.dart` 공용 발신 헬퍼 + 상세 화면 정리

**Files:**
- Create: `app/lib/dial.dart`
- Create: `app/test/dial_test.dart`
- Modify: `app/lib/screens/fall_detail.dart` (import 정리, `_emergencyPhone`·`_dial` 삭제, 호출부 교체)
- Modify: `app/pubspec.yaml` (dev_dependencies에 `url_launcher_platform_interface: ^2.3.0` 추가 후 `flutter pub get` — 테스트가 플랫폼 구현을 페이크로 교체하기 위해. pubspec.lock 변동도 커밋)

**Interfaces:**
- Consumes: 없음 (url_launcher는 pubspec에 이미 있다)
- Produces: `lib/dial.dart`의 `const emergencyPhone = '01000000119';` 와
  `Future<void> dial(BuildContext context, String number)` — Task 2가 이 둘을 그대로 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

먼저 `app/pubspec.yaml`의 `dev_dependencies`에 `url_launcher_platform_interface: ^2.3.0`을
추가하고 `flutter pub get`을 실행한다.

> **왜 페이크인가:** Windows 호스트의 `flutter test`는 Dart 플러그인 레지스트런트를 실행해
> `url_launcher_windows`의 Dart 구현이 진짜로 등록된다 — `launchUrl`이 예외를 던지는 게
> 아니라 실제로 열려서 true를 돌려준다(호스트에서 전화 앱이 열릴 수도 있다). 채널 모킹도
> Dart 구현은 채널을 안 쓰므로 소용없다. url_launcher의 공식 테스트 방식대로
> `UrlLauncherPlatform.instance`를 페이크로 교체한다.

`app/test/dial_test.dart` 생성:

```dart
// 전화 발신 헬퍼 — 전화 앱을 못 여는 환경에서 스낵바로 알리는지

import 'package:fall_guardian/dial.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// 실제 플랫폼 구현 대신 꽂는 페이크 — Windows 호스트에서는 진짜 런처가 등록되므로
// 교체하지 않으면 테스트가 호스트에서 전화 앱을 연다.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({this.result = false, this.throwInstead = false});

  final bool result;
  final bool throwInstead;
  String? lastUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastUrl = url;
    if (throwInstead) throw PlatformException(code: 'launch_failed');
    return result;
  }
}

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => dial(context, '01012345678'),
          child: const Text('걸기'),
        ),
      ),
    ),
  ));
}

// 스낵바 표시 타이머(기본 4초)를 소진한다 — pending timer로 테스트가 깨지지 않게
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('전화 앱을 못 열면 스낵바가 뜬다', (tester) async {
    UrlLauncherPlatform.instance = _FakeUrlLauncher(result: false);
    await _pumpHost(tester);

    await tester.tap(find.text('걸기'));
    await tester.pumpAndSettle();

    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);

    await _drainSnackBar(tester);
  });

  testWidgets('launchUrl이 예외를 던져도 스낵바로 흡수한다', (tester) async {
    UrlLauncherPlatform.instance = _FakeUrlLauncher(throwInstead: true);
    await _pumpHost(tester);

    await tester.tap(find.text('걸기'));
    await tester.pumpAndSettle();

    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);

    await _drainSnackBar(tester);
  });

  testWidgets('전화 앱이 열리면 tel: 주소로 걸고 스낵바가 없다', (tester) async {
    final launcher = _FakeUrlLauncher(result: true);
    UrlLauncherPlatform.instance = launcher;
    await _pumpHost(tester);

    await tester.tap(find.text('걸기'));
    await tester.pumpAndSettle();

    expect(launcher.lastUrl, 'tel:01012345678');
    expect(find.text('전화 앱을 열 수 없습니다.'), findsNothing);
  });
}
```

주의: `UrlLauncherPlatform`의 추상 멤버가 위 오버라이드 외에 더 있다고 analyzer가 요구하면,
요구하는 멤버만 무해한 기본값으로 추가 구현한다. `link.dart` import가 없는 버전이면
`linkDelegate` 오버라이드와 해당 import를 함께 제거한다.

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/dial_test.dart`
Expected: 컴파일 실패 — `Error: Couldn't resolve the package 'fall_guardian/dial.dart'` 류 (파일이 없다).

- [ ] **Step 3: `lib/dial.dart` 구현**

```dart
// 전화 발신 공용 헬퍼 — 알림 상세 화면과 사고 발생 창이 같이 쓴다

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 119 신고용 번호 — 시연용 상수다. 실제 번호로 바꾸는 날 고칠 곳은 여기 하나다.
const emergencyPhone = '01000000119';

/// [number]로 전화 앱을 연다. 못 열면(미지원 환경·전화 앱 없음·플러그인 예외)
/// "전화 앱을 열 수 없습니다." 스낵바를 띄운다.
Future<void> dial(BuildContext context, String number) async {
  // async 갭 이전에 메신저를 잡아 두면 부른 위젯이 먼저 사라져도 안전하다
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri(scheme: 'tel', path: number);
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false; // launchUrl은 환경에 따라 false 대신 예외를 던지기도 한다
  }
  if (!ok) {
    messenger.showSnackBar(const SnackBar(content: Text('전화 앱을 열 수 없습니다.')));
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/dial_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: `fall_detail.dart`가 공용 헬퍼를 쓰도록 정리**

`app/lib/screens/fall_detail.dart`에서:

1. import 교체 — `import 'package:url_launcher/url_launcher.dart';` 삭제, `import '../dial.dart';` 추가 (상대 import 블록에, 알파벳순으로 `../api.dart` 앞).
2. 멤버 삭제 — 아래 둘을 통째로 지운다:

```dart
  static const _emergencyPhone = '01000000119';

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('전화 앱을 열 수 없습니다.')));
    }
  }
```

3. 호출부 두 곳 교체:

```dart
// 돌봄 대상자에게 전화 (변경 전 → 후)
onPressed: phoneRegistered ? () => _dial(_elderPhone!) : null,
onPressed: phoneRegistered ? () => dial(context, _elderPhone!) : null,

// 119 긴급 신고 (변경 전 → 후)
onPressed: _event.isReported119 ? null : () => _dial(_emergencyPhone),
onPressed: _event.isReported119 ? null : () => dial(context, emergencyPhone),
```

- [ ] **Step 6: 회귀 확인**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: 전부 PASS — `fall_detail_test.dart`는 수정 없이 통과해야 한다(동작 불변 확인).

- [ ] **Step 7: 커밋**

```bash
git add app/lib/dial.dart app/test/dial_test.dart app/lib/screens/fall_detail.dart app/pubspec.yaml app/pubspec.lock
git commit -m "refactor: 전화 발신을 dial.dart로 공용화 — launchUrl 예외도 스낵바로 흡수"
```

---

### Task 2: 사고 발생 창에 전화·119 버튼

**Files:**
- Modify: `app/lib/screens/fall_alert_dialog.dart` (전체 교체 — Stateless → Stateful)
- Modify: `app/lib/screens/main_shell.dart:111` (호출부에 `api:` 전달)
- Modify: `app/test/fall_alert_dialog_test.dart` (전체 교체 — FakeApi 주입 + 신규 테스트)
- Modify: `app/test/main_shell_alert_test.dart` (`_FakeApi`에 `getProfile` 오버라이드 추가)

**Interfaces:**
- Consumes: Task 1의 `dial(BuildContext context, String number)`·`emergencyPhone` (`lib/dial.dart`).
- Produces: `FallAlertDialog({required Api api, required FallEvent event})` — 호출부는 `main_shell.dart` 하나뿐이다.

- [ ] **Step 1: 실패하는 테스트 작성 — `app/test/fall_alert_dialog_test.dart` 전체 교체**

기존 5개 테스트는 유지하되 열기 헬퍼가 FakeApi를 주입하게 바꾸고, 전화·119 테스트 6개를 더한다:

```dart
// 사고 발생 창 — 방·시각 표시, "확인이 유일한 출구", 전화·119 버튼

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// 실패만 돌려주는 페이크 런처 — Windows 호스트의 flutter test는 진짜 런처를 등록할 수
// 있어, 교체하지 않으면 버튼 탭 테스트가 호스트에서 전화 앱을 연다. (dial_test와 같은 이유)
class _FakeUrlLauncher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => false;
}

class _FakeApi extends Api {
  _FakeApi({this.elderPhone = ''});

  final String elderPhone;

  @override
  Future<Profile> getProfile() async => Profile(elderPhone: elderPhone);
}

FallEvent _event({DateTime? reported119At}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 2,
      occurredAt: DateTime(2026, 7, 28, 4, 35),
      createdAt: DateTime(2026, 7, 28, 4, 35),
      confidence: 0.9,
      reported119At: reported119At,
    );

Future<void> _open(
  WidgetTester tester, {
  bool dark = false,
  String elderPhone = '',
  DateTime? reported119At,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(dark: dark, scale: TextScale.normal),
    // 스낵바가 실제로 그려지려면 ScaffoldMessenger에 등록된 Scaffold가 필요하다
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            barrierDismissible: false,
            useRootNavigator: true,
            builder: (_) => FallAlertDialog(
              api: _FakeApi(elderPhone: elderPhone),
              event: _event(reported119At: reported119At),
            ),
          ),
          child: const Text('열기'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

// 라벨로 버튼 위젯을 찾는다 — 활성/비활성(onPressed) 검사용. fall_detail_test와 같은 방식.
Finder _phoneButton() => find.ancestor(
      of: find.text('돌봄 대상자에게 전화'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );

Finder _emergencyButton() => find.ancestor(
      of: find.text('119 긴급 신고'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );

// 스낵바 표시 타이머(기본 4초)를 소진한다 — pending timer로 테스트가 깨지지 않게
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // 모든 테스트에서 진짜 런처를 차단한다 — 탭 테스트는 실패 경로(스낵바)로 고정된다
    UrlLauncherPlatform.instance = _FakeUrlLauncher();
  });

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

  testWidgets('번호가 등록돼 있으면 전화 버튼이 활성이고 안내문이 없다', (tester) async {
    await _open(tester, elderPhone: '01012345678');

    expect(tester.widget<OutlinedButton>(_phoneButton()).onPressed, isNotNull);
    expect(find.text('프로필에서 전화번호를 등록하면 켜집니다.'), findsNothing);
  });

  testWidgets('번호가 없으면 전화 버튼이 비활성이고 안내문이 보인다', (tester) async {
    await _open(tester);

    expect(tester.widget<OutlinedButton>(_phoneButton()).onPressed, isNull);
    expect(find.text('프로필에서 전화번호를 등록하면 켜집니다.'), findsOneWidget);
  });

  testWidgets('신고 전에는 119 버튼이 활성이고 자동 신고 문구가 없다', (tester) async {
    await _open(tester);

    expect(tester.widget<FilledButton>(_emergencyButton()).onPressed, isNotNull);
    expect(find.text('응답이 없어 119에 자동 신고되었습니다'), findsNothing);
  });

  testWidgets('신고된 이벤트는 119 버튼이 잠기고 자동 신고 문구가 보인다', (tester) async {
    await _open(tester, reported119At: DateTime(2026, 7, 28, 4, 36));

    expect(tester.widget<FilledButton>(_emergencyButton()).onPressed, isNull);
    expect(find.text('응답이 없어 119에 자동 신고되었습니다'), findsOneWidget);
  });

  testWidgets('전화 버튼을 눌러도 창은 유지된다', (tester) async {
    await _open(tester, elderPhone: '01012345678');

    await tester.tap(find.text('돌봄 대상자에게 전화'));
    await tester.pumpAndSettle();

    // 페이크 런처가 실패를 돌려줘 스낵바가 뜨고 창은 남는다
    expect(find.text('사고 발생'), findsOneWidget);
    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);

    await _drainSnackBar(tester);
  });

  testWidgets('119 버튼을 눌러도 창은 유지된다', (tester) async {
    await _open(tester);

    await tester.tap(find.text('119 긴급 신고'));
    await tester.pumpAndSettle();

    expect(find.text('사고 발생'), findsOneWidget);
    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);

    await _drainSnackBar(tester);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/fall_alert_dialog_test.dart`
Expected: 컴파일 실패 — `No named parameter with the name 'api'` (창이 아직 api를 안 받는다).

- [ ] **Step 3: `fall_alert_dialog.dart` 구현 — 전체 교체**

```dart
// 낙상 발생 알림 창 — 방·시각을 보여주고 확인 버튼으로만 닫힌다.
// 상세 화면과 같은 전화·119 버튼을 갖는다. 전화를 걸어도 창은 유지된다.

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../dial.dart';
import '../models.dart';

class FallAlertDialog extends StatefulWidget {
  const FallAlertDialog({super.key, required this.api, required this.event});

  final Api api;
  final FallEvent event;

  @override
  State<FallAlertDialog> createState() => _FallAlertDialogState();
}

class _FallAlertDialogState extends State<FallAlertDialog> {
  // null = 조회 중. 실패하면 '' — 전화 버튼 비활성 + 안내문 (상세 화면과 같다)
  String? _elderPhone;

  @override
  void initState() {
    super.initState();
    widget.api.getProfile().then((p) {
      if (mounted) setState(() => _elderPhone = p.elderPhone);
    }).catchError((_) {
      if (mounted) setState(() => _elderPhone = '');
    });
  }

  // 홈·알림 목록과 같은 형식이다
  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final event = widget.event;
    final phoneRegistered = _elderPhone != null && _elderPhone!.isNotEmpty;
    // 상세 화면 _actionButton과 같은 비활성 색 — onSurface에 Material 알파(배경 12% · 전경 38%)
    final disabledBg = scheme.onSurface.withValues(alpha: 0.12);
    final disabledFg = scheme.onSurface.withValues(alpha: 0.38);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return PopScope(
      // 뒤로가기·스와이프로 닫히지 않는다. 부르는 쪽의 barrierDismissible: false와
      // 합쳐져 확인 버튼이 유일한 출구가 된다. 전화·119 버튼은 창을 닫지 않는다.
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
          // AlertDialog의 가로 OverflowBar 대신 Column으로 세로 스택 — 간격을 직접
          // 제어하고 안내문을 버튼 바로 아래 붙인다
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 돌봄 대상자에게 전화 — 미등록이면 비활성 + 안내
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: phoneRegistered ? () => dial(context, _elderPhone!) : null,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: scheme.surfaceContainer,
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outline),
                    disabledForegroundColor: disabledFg,
                    shape: shape,
                  ),
                  child: _buttonLabel(Icons.phone, '돌봄 대상자에게 전화'),
                ),
              ),
              if (!phoneRegistered) ...[
                const SizedBox(height: 8),
                Text(
                  '프로필에서 전화번호를 등록하면 켜집니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              // 119 긴급 신고 — 이미 자동 신고된 이벤트면 잠근다
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: event.isReported119 ? null : () => dial(context, emergencyPhone),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: disabledBg,
                    disabledForegroundColor: disabledFg,
                    shape: shape,
                  ),
                  child: _buttonLabel(Icons.warning_amber, '119 긴급 신고'),
                ),
              ),
              if (event.isReported119) ...[
                const SizedBox(height: 8),
                Text(
                  '응답이 없어 119에 자동 신고되었습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: shape,
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 상세 화면 _actionButton의 안쪽 Row와 같은 구성이다
  Widget _buttonLabel(IconData icon, String label) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      );

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

- [ ] **Step 4: `main_shell.dart` 호출부에 api 전달**

`app/lib/screens/main_shell.dart:111` 한 줄 교체:

```dart
// 변경 전
builder: (_) => FallAlertDialog(event: event),
// 변경 후
builder: (_) => FallAlertDialog(api: widget.api, event: event),
```

- [ ] **Step 5: `main_shell_alert_test.dart`의 `_FakeApi`에 getProfile 추가**

창이 이제 열릴 때 `getProfile()`을 부른다. 테스트 프레임워크의 HTTP 400 스텁에 기대지 않도록
`_FakeApi`(`app/test/main_shell_alert_test.dart`)의 `acknowledge` 오버라이드 아래에 추가:

```dart
  @override
  Future<Profile> getProfile() async => const Profile(elderPhone: '');
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `flutter test test/fall_alert_dialog_test.dart`
Expected: PASS (11 tests)

Run: `flutter test test/main_shell_alert_test.dart`
Expected: PASS

- [ ] **Step 7: 회귀 전체**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: 전부 PASS.

- [ ] **Step 8: 커밋**

```bash
git add app/lib/screens/fall_alert_dialog.dart app/lib/screens/main_shell.dart app/test/fall_alert_dialog_test.dart app/test/main_shell_alert_test.dart
git commit -m "feat: 사고 발생 창에 돌봄 대상자 전화·119 긴급 신고 버튼"
```
