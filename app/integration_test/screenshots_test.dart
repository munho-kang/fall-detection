// 문서용 스크린샷 자동 촬영 — 서버 없이 가짜 Api로 12개 화면을 띄워 docs/screenshots/*.png로 남긴다.
// 실행: cd app && flutter drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/screenshots_test.dart -d <시뮬레이터 UDID>
// 디자인을 바꾼 뒤 이 명령 한 번이면 README가 참조하는 스크린샷이 전부 갱신된다.

import 'dart:io';

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/local_store.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/login.dart';
import 'package:fall_guardian/screens/main_shell.dart';
import 'package:fall_guardian/screens/settings.dart';
import 'package:fall_guardian/screens/signup.dart';
import 'package:fall_guardian/screens/splash.dart';
import 'package:fall_guardian/screens/start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

FallEvent _ev(int id, String room, int number, DateTime at, {DateTime? ack, DateTime? ok, DateTime? r119}) =>
    FallEvent(
      id: id,
      roomName: room,
      roomNumber: number,
      occurredAt: at,
      createdAt: at,
      confidence: 0.93,
      acknowledgedAt: ack,
      voiceOkAt: ok,
      reported119At: r119,
    );

const _rooms = [
  Room(id: 1, name: '거실', number: 1),
  Room(id: 2, name: '침실', number: 2),
  Room(id: 3, name: '화장실', number: 3),
];

final _unread = _ev(4, '거실', 1, DateTime(2026, 8, 5, 14, 32));
final _history = [
  _ev(3, '침실', 2, DateTime(2026, 8, 4, 21, 7), ack: DateTime(2026, 8, 4, 21, 30)),
  _ev(2, '거실', 1, DateTime(2026, 8, 3, 9, 15), ack: DateTime(2026, 8, 3, 9, 20), ok: DateTime(2026, 8, 3, 9, 16)),
  _ev(1, '화장실', 3, DateTime(2026, 8, 1, 7, 42), ack: DateTime(2026, 8, 1, 7, 50), r119: DateTime(2026, 8, 1, 7, 43)),
];

// 폴링 응답을 순서대로 준다. 목록이 떨어지면 마지막 응답을 반복한다.
class _FakeApi extends Api {
  _FakeApi(this.responses);

  final List<List<FallEvent>> responses;
  int _calls = 0;

  @override
  Future<String?> loadToken() async => null;

  @override
  Future<List<FallEvent>> listFalls() async {
    final i = _calls < responses.length ? _calls : responses.length - 1;
    _calls++;
    return responses[i];
  }

  @override
  Future<List<Room>> listRooms() async => _rooms;

  @override
  Future<Profile> getProfile() async => const Profile(elderPhone: '010-9876-5432');

  @override
  Future<FallEvent> acknowledge(int id) async => responses.last.firstWhere((e) => e.id == id);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 시뮬레이터가 프레임을 늦게 주면 pumpAndSettle이 기본 10분을 기다린다 — 5초면 화면은 이미 안정돼 있다
  Future<void> settle(WidgetTester tester) async {
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    } on FlutterError {
      // 시간 초과 — 그대로 진행한다
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot(name);
  }

  Widget app(Widget home) => MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: home);

  Finder tab(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  setUpAll(() async {
    // OS 알림·권한 창이 캡처를 덮지 않게 끈다. 프로필 화면에 보일 이름·연락처도 심는다.
    await LocalStore.setNotificationsOn(false);
    await LocalStore.setNickname('보호자님');
    await LocalStore.setContactPhone('');
    await LocalStore.setTextScale(TextScale.normal);
  });

  testWidgets('01~04 시작 흐름', (tester) async {
    final api = _FakeApi([_history]);
    await tester.pumpWidget(app(SplashScreen(api: api, onDone: (_) {})));
    await shot(tester, '01-splash');

    await tester.pumpWidget(app(StartScreen(api: api)));
    await shot(tester, '02-start');

    await tester.pumpWidget(app(LoginScreen(api: api)));
    await shot(tester, '03-login');

    await tester.pumpWidget(app(SignupScreen(api: api)));
    await shot(tester, '04-signup');
  });

  testWidgets('05 홈 — 미확인 없음', (tester) async {
    await tester.pumpWidget(app(MainShell(api: _FakeApi([_history]))));
    await shot(tester, '05-home');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('06~09 사고 발생 창 → 홈(미확인) → 알림 목록 → 상세', (tester) async {
    // 첫 폴링은 프라이밍(창 없음), 다음 틱부터 새 낙상이 들어온다
    final api = _FakeApi([_history, [_unread, ..._history]]);
    await tester.pumpWidget(app(MainShell(api: api)));
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 6)); // 폴러 5초 주기 한 번(실제 시간)
    await shot(tester, '06-fall-alert-dialog');

    await tester.tap(find.text('확인'));
    await shot(tester, '07-home-unread');

    await tester.tap(find.byIcon(Icons.notifications_outlined).first);
    await shot(tester, '08-fall-list');

    await tester.tap(find.text('거실 1').first);
    await shot(tester, '09-fall-detail');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('10~14 방 관리 · 프로필 · 설정', (tester) async {
    await tester.pumpWidget(app(MainShell(api: _FakeApi([_history]))));
    await tester.pumpAndSettle();

    await tester.tap(tab('방 관리'));
    await shot(tester, '10-rooms');
    await tester.tap(find.text('방 추가'));
    await shot(tester, '11-room-add-dialog');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    await tester.tap(tab('프로필'));
    await shot(tester, '12-profile');
    // 탈퇴 줄은 화면 아래에 가려져 있다 — 스크롤해 보이게 한 뒤 누른다(안 그러면 하단 탭이 눌린다)
    await tester.ensureVisible(find.text('회원 탈퇴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('회원 탈퇴'));
    await shot(tester, '13-withdraw-dialog');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 설정 화면은 알림이 켜진 평소 모습으로 — 폴러는 이미 내려갔으니 알림 창이 뜰 일이 없다
    await LocalStore.setNotificationsOn(true);
    await tester.pumpWidget(app(const SettingsScreen()));
    await shot(tester, '14-settings');
  });
}
