// 목록 trailing 우선순위 검증 — 119 신고됨 > 괜찮다고 말함 > 확인함/미확인

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends Api {
  _FakeApi(this.events);

  final List<FallEvent> events;

  @override
  Future<List<FallEvent>> listFalls() async => events;
}

FallEvent _event({DateTime? voiceOkAt, DateTime? reported119At}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 27, 12),
      createdAt: DateTime(2026, 7, 27, 12),
      confidence: 0.9,
      voiceOkAt: voiceOkAt,
      reported119At: reported119At,
    );

Future<void> _pumpList(WidgetTester tester, FallEvent event) async {
  await tester.pumpWidget(MaterialApp(home: FallListScreen(api: _FakeApi([event]))));
  await tester.pump(); // listFalls 완료
  await tester.pump(); // setState 반영
}

void main() {
  testWidgets('괜찮다고 답한 이벤트는 trailing이 "괜찮다고 말함"이다', (tester) async {
    await _pumpList(tester, _event(voiceOkAt: DateTime(2026, 7, 27, 12, 0, 12)));

    expect(find.text('괜찮다고 말함'), findsOneWidget);
    expect(find.text('미확인'), findsNothing);
  });

  testWidgets('신고와 괜찮음이 둘 다면 119 신고됨이 이긴다', (tester) async {
    // 상태머신 정상 경로엔 없지만, 표시 우선순위는 안전 쪽이 이겨야 한다
    await _pumpList(
      tester,
      _event(
        voiceOkAt: DateTime(2026, 7, 27, 12, 0, 12),
        reported119At: DateTime(2026, 7, 27, 12, 0, 20),
      ),
    );

    expect(find.text('119 신고됨'), findsOneWidget);
    expect(find.text('괜찮다고 말함'), findsNothing);
  });
}
