// 공통 위젯 — 상태 문구 우선순위 · 시각 형식 · 타일 구성 · 동작 버튼 비활성

import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent _event({DateTime? ack, DateTime? r119, DateTime? ok}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 8, 4, 21, 7),
      createdAt: DateTime(2026, 8, 4, 21, 7),
      confidence: 0.9,
      acknowledgedAt: ack,
      reported119At: r119,
      voiceOkAt: ok,
    );

void main() {
  final t = DateTime(2026, 8, 5);

  test('상태 문구 — 119 신고됨 > 괜찮다고 말함 > 확인함/미확인', () {
    expect(statusLabel(_event()), '미확인');
    expect(statusLabel(_event(ack: t)), '확인함');
    expect(statusLabel(_event(ack: t, ok: t)), '괜찮다고 말함');
    expect(statusLabel(_event(ok: t, r119: t)), '119 신고됨');
  });

  test('짧은 시각 형식은 월 일 시:분', () {
    expect(fmtShort(DateTime(2026, 8, 4, 21, 7)), '8월 4일 21:07');
  });

  testWidgets('타일은 방 이름·시각·상태 칩을 그린다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: FallTile(event: _event(ok: t), onTap: () {})),
    ));
    expect(find.text('안방 1'), findsOneWidget);
    expect(find.text('8월 4일 21:07'), findsOneWidget);
    expect(find.text('괜찮다고 말함'), findsOneWidget);
  });

  testWidgets('동작 버튼은 onPressed가 없으면 눌리지 않는다', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [
          ActionButton(label: '켜짐', kind: ActionKind.emergency, onPressed: () => pressed++),
          const ActionButton(label: '꺼짐', kind: ActionKind.emergency, onPressed: null),
        ]),
      ),
    ));
    await tester.tap(find.text('켜짐'));
    await tester.tap(find.text('꺼짐'));
    expect(pressed, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '꺼짐')).enabled, isFalse);
  });
}
