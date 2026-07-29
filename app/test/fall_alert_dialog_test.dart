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
