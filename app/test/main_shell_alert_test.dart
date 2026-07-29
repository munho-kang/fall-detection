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
