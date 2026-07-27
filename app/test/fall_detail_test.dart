// 상세 화면 검증 — 119 버튼 잠금·괜찮음 음성 확인 행

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends Api {
  @override
  Future<Profile> getProfile() async => const Profile(elderPhone: '');

  @override
  Future<List<FallEvent>> listFalls() async => [];
}

FallEvent _event({DateTime? reported119At, DateTime? voiceOkAt}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 27, 12),
      createdAt: DateTime(2026, 7, 27, 12),
      confidence: 0.9,
      reported119At: reported119At,
      voiceOkAt: voiceOkAt,
    );

// OutlinedButton.icon은 OutlinedButton의 비공개 서브클래스를 만들므로 byType으로는 못 찾는다
Finder _emergencyButton() => find.ancestor(
      of: find.text('119 신고 (시연용 더미 번호)'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );

void main() {
  testWidgets('신고된 이벤트는 119 버튼이 잠기고 자동 신고 문구가 보인다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FallDetailScreen(
        api: _FakeApi(),
        event: _event(reported119At: DateTime(2026, 7, 27, 12, 0, 20)),
      ),
    ));
    await tester.pump();

    expect(tester.widget<OutlinedButton>(_emergencyButton()).onPressed, isNull);
    expect(find.text('응답이 없어 119에 자동 신고되었습니다'), findsOneWidget);
  });

  testWidgets('신고 전에는 119 버튼이 활성이고 문구가 없다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FallDetailScreen(api: _FakeApi(), event: _event()),
    ));
    await tester.pump();

    expect(tester.widget<OutlinedButton>(_emergencyButton()).onPressed, isNotNull);
    expect(find.text('응답이 없어 119에 자동 신고되었습니다'), findsNothing);
  });

  testWidgets('괜찮다고 답한 이벤트는 음성 확인 행이 보인다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FallDetailScreen(
        api: _FakeApi(),
        event: _event(voiceOkAt: DateTime(2026, 7, 27, 12, 0, 12)),
      ),
    ));
    await tester.pump();

    expect(find.text('음성 확인'), findsOneWidget);
    expect(find.text('낙상자가 괜찮다고 말했습니다 (2026년 7월 27일 12:00:12)'), findsOneWidget);
  });

  testWidgets('괜찮음 응답이 없으면 음성 확인 행이 없다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FallDetailScreen(api: _FakeApi(), event: _event()),
    ));
    await tester.pump();

    expect(find.text('음성 확인'), findsNothing);
  });
}
