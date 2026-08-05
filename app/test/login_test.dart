// 로그인 성공 후 라우트 스택 — 시작 화면이 아래 남아 있으면 로그인된 홈에
// 뒤로가기 화살표가 생기고, 누르면 로그아웃도 아닌 채 시작 화면으로 나가진다.

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/login.dart';
import 'package:fall_guardian/screens/main_shell.dart';
import 'package:fall_guardian/screens/start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends Api {
  @override
  Future<String> login(String username, String password) async => 'tok';

  @override
  Future<String> signup(String username, String password) async => 'tok';

  @override
  Future<List<FallEvent>> listFalls() async => const [];

  @override
  Future<List<Room>> listRooms() async => const [];

  @override
  Future<Profile> getProfile() async => const Profile(elderPhone: '');
}

// MainShell의 폴러 타이머가 테스트 종료까지 남지 않게 트리를 비운다
Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'local.notifications_on': false}));

  testWidgets('시작 → 로그인 → 홈이면 뒤로 갈 화면이 남지 않는다', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: StartScreen(api: api)));

    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(StartScreen, skipOffstage: false), findsNothing);
    expect(Navigator.of(tester.element(find.byType(MainShell))).canPop(), isFalse);

    await _disposeShell(tester);
  });

  testWidgets('로그인 화면의 회원가입으로 들어가 가입해도 뒤로 갈 화면이 없다', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: StartScreen(api: api)));

    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계정이 없나요? 회원가입'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'abcd1234!');
    await tester.enterText(find.byType(TextField).at(2), 'abcd1234!');
    await tester.tap(find.widgetWithText(FilledButton, '가입하기'));
    await tester.pumpAndSettle();

    expect(find.byType(MainShell), findsOneWidget);
    expect(Navigator.of(tester.element(find.byType(MainShell))).canPop(), isFalse);

    await _disposeShell(tester);
  });
}
