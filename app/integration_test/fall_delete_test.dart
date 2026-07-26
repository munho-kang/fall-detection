// iOS 시뮬레이터에서 낙상 기록 삭제 흐름을 실제 서버와 함께 검증하는 통합 테스트
//
// docs/manual-verification.md 7절의 "앱 (iOS)"·"양쪽 동기화" 항목을 자동으로 밟는다.
// 실행 전 백엔드가 127.0.0.1:8000에 떠 있어야 한다.
//   flutter test integration_test/fall_delete_test.dart -d <시뮬레이터 UDID>

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/screens/fall_detail.dart';
import 'package:fall_guardian/screens/fall_list.dart';

const _base = 'http://127.0.0.1:8000';
const _password = 'Sim!Verify2026';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api api;
  late String token;
  late String user;

  setUp(() async {
    // 테스트마다 새 계정을 쓴다. 앞 테스트가 남긴 기록이 목록에 섞이면 판정이 흔들린다.
    user = 'simtest_${DateTime.now().microsecondsSinceEpoch}';
    final res = await http.post(
      Uri.parse('$_base/api/auth/signup/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': user, 'password': _password}),
    );
    expect(res.statusCode, 201, reason: '가입 실패: ${res.body}');
    token = jsonDecode(res.body)['token'] as String;

    api = Api();
    await api.login(user, _password);
  });

  /// 낙상 1건을 서버에 넣고 id를 준다.
  Future<int> seedFall(String roomName, int roomNumber) async {
    final res = await http.post(
      Uri.parse('$_base/api/falls/'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Token $token'},
      body: jsonEncode({
        'room_name': roomName,
        'room_number': roomNumber,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'confidence': 0.9,
      }),
    );
    expect(res.statusCode, 201, reason: '낙상 생성 실패: ${res.body}');
    return jsonDecode(res.body)['id'] as int;
  }

  Future<int> countFallsOnServer() async {
    final res = await http.get(
      Uri.parse('$_base/api/falls/'),
      headers: {'Authorization': 'Token $token'},
    );
    return (jsonDecode(res.body) as List).length;
  }

  /// 목록 화면을 띄우고 첫 폴링이 그려질 때까지 기다린다.
  Future<void> openList(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4C8DFF), useMaterial3: true),
      home: FallListScreen(api: api),
    ));
    await tester.pumpAndSettle();
  }

  /// 목록 항목을 눌러 상세 화면으로 들어간다.
  Future<void> openDetail(WidgetTester tester, String roomLabel) async {
    await tester.tap(find.text(roomLabel));
    await tester.pumpAndSettle();
    expect(find.byType(FallDetailScreen), findsOneWidget);
  }

  /// 라벨로 버튼을 찾아 활성 여부를 읽는다.
  bool isButtonEnabled(WidgetTester tester, String label) {
    final button = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)),
    );
    return button.onPressed != null;
  }

  testWidgets('미확인 기록 — 삭제 버튼이 비활성이고 라벨이 "확인한 뒤 삭제할 수 있습니다"', (tester) async {
    await seedFall('안방', 1);
    await openList(tester);
    await openDetail(tester, '안방 1');

    expect(find.text('미확인'), findsOneWidget);
    expect(find.text('확인한 뒤 삭제할 수 있습니다'), findsOneWidget);
    expect(find.text('기록 삭제'), findsNothing);
    expect(isButtonEnabled(tester, '확인한 뒤 삭제할 수 있습니다'), isFalse);
  });

  testWidgets('확인함으로 표시 — 삭제 버튼이 활성되고 라벨이 "기록 삭제"로 바뀐다', (tester) async {
    await seedFall('거실', 2);
    await openList(tester);
    await openDetail(tester, '거실 2');

    await tester.tap(find.text('확인함으로 표시'));
    await tester.pumpAndSettle();

    expect(find.text('기록 삭제'), findsOneWidget);
    expect(find.text('확인한 뒤 삭제할 수 있습니다'), findsNothing);
    expect(isButtonEnabled(tester, '기록 삭제'), isTrue);
  });

  testWidgets('삭제 다이얼로그 취소 — 상세 화면에 머물고 기록도 그대로다', (tester) async {
    await seedFall('주방', 3);
    await openList(tester);
    await openDetail(tester, '주방 3');

    await tester.tap(find.text('확인함으로 표시'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('기록을 삭제할까요?'), findsOneWidget);
    expect(find.textContaining('삭제하면 되돌릴 수 없습니다.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(find.byType(FallDetailScreen), findsOneWidget);
    expect(find.text('기록을 삭제할까요?'), findsNothing);
    expect(await countFallsOnServer(), 1);
  });

  testWidgets('삭제 확정 — 목록으로 돌아가고 항목이 즉시 사라진다 (5초 폴링을 기다리지 않는다)', (tester) async {
    await seedFall('안방', 4);
    await openList(tester);
    await openDetail(tester, '안방 4');

    await tester.tap(find.text('확인함으로 표시'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));

    // 폴링 주기(5초)의 절반도 지나기 전에 목록이 갱신되어야 한다.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(FallListScreen), findsOneWidget);
    expect(find.text('안방 4'), findsNothing);
    expect(find.text('아직 감지된 낙상이 없습니다.'), findsOneWidget);
    expect(await countFallsOnServer(), 0);
  });

  testWidgets('스와이프 백 — 같은 null 경로를 타고 목록이 정상으로 남는다', (tester) async {
    await seedFall('안방', 5);
    await seedFall('거실', 6);
    await openList(tester);
    await openDetail(tester, '안방 5');

    // iOS 뒤로 가기 제스처. 왼쪽 가장자리에서 오른쪽으로 끈다.
    await tester.dragFrom(const Offset(2, 400), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.byType(FallListScreen), findsOneWidget);
    expect(find.byType(FallDetailScreen), findsNothing);
    expect(find.text('안방 5'), findsOneWidget);
    expect(find.text('거실 6'), findsOneWidget);
  });

  testWidgets('양쪽 동기화 — 서버에서 지운 기록이 5초 안에 앱 목록에서 사라진다', (tester) async {
    final id = await seedFall('안방', 7);
    await seedFall('거실', 8);
    await openList(tester);
    expect(find.text('안방 7'), findsOneWidget);

    // 웹에서 삭제한 상황을 그대로 만든다 — 확인한 뒤 서버에서 지운다.
    await api.acknowledge(id);
    final res = await http.delete(
      Uri.parse('$_base/api/falls/$id/'),
      headers: {'Authorization': 'Token $token'},
    );
    expect(res.statusCode, 204);

    // 앱은 아무 조작도 하지 않는다. 폴링 한 주기만 기다린다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('안방 7'), findsNothing);
    expect(find.text('거실 8'), findsOneWidget);
  });
}
