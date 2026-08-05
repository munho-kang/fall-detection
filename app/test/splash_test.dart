// 스플래시 레이아웃 — Scaffold body는 가로 constraints를 느슨하게 주므로
// Column이 기본 center 정렬만 믿으면 가장 넓은 자식 폭으로 수축해 왼쪽에 붙는다.

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/screens/splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends Api {
  @override
  Future<String?> loadToken() async => null;
}

void main() {
  testWidgets('로고와 문구가 화면 가로 중앙에 온다 (에뮬레이터 1080x2400)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(api: _FakeApi(), onDone: (_) {}),
    ));
    await tester.pump();

    final center = tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;
    expect(tester.getCenter(find.byIcon(Icons.shield_outlined)).dx, closeTo(center, 0.5));
    expect(tester.getCenter(find.text('낙상 알림')).dx, closeTo(center, 0.5));
    expect(tester.getCenter(find.text('프라이버시 보존형 낙상 감지')).dx, closeTo(center, 0.5));

    await tester.pump(const Duration(seconds: 2)); // _boot의 최소 노출 타이머 소화
  });

  testWidgets('좁은 화면에서도 문구가 가로로 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(api: _FakeApi(), onDone: (_) {}),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });
}
