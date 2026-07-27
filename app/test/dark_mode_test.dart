// 다크 테마로 각 화면을 띄워 대표 글자색이 다크 값인지 본다 —
// 라이트 상수가 화면에 하드코딩돼 있으면 여기서 잡힌다

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 다크 테마의 값 — app_theme.dart와 맞춘다
const darkOnSurface = Color(0xFFE2E6E5);
const darkOnSurfaceVariant = Color(0xFFBFC9C6);
const darkOnPrimaryContainer = Color(0xFFB8E7DD);

Future<void> pumpDark(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(dark: true, scale: TextScale.normal),
    home: screen,
  ));
  await tester.pump();
}

Color? colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('홈 — 섹션 제목과 방 추가 배너가 다크 글자색이다', (tester) async {
    await pumpDark(
      tester,
      HomeScreen(
        events: const [],
        rooms: const [],
        loadingEvents: false,
        loadingRooms: false,
        connectionError: null,
        unreadCount: 0,
        onGoNotifications: () {},
        onGoSettings: () {},
        onChangeTab: (_) {},
        api: Api(),
        onLogout: () {},
      ),
    );

    // 카드 밖 페이지 배경 위에 바로 놓인 글자 — 배경만 고치면 사라지는 자리다
    expect(colorOf(tester, '확인하지 않은 알림'), darkOnSurface);
    expect(colorOf(tester, '방 추가'), darkOnPrimaryContainer);
  });

  testWidgets('홈 — 연결 끊김 배너 글자가 다크 errorContainer 위 색이다', (tester) async {
    await pumpDark(
      tester,
      HomeScreen(
        events: const [],
        rooms: const [],
        loadingEvents: false,
        loadingRooms: false,
        connectionError: '서버와 연결이 끊겼습니다.',
        unreadCount: 0,
        onGoNotifications: () {},
        onGoSettings: () {},
        onChangeTab: (_) {},
        api: Api(),
        onLogout: () {},
      ),
    );

    expect(colorOf(tester, '서버와 연결이 끊겼습니다.'), const Color(0xFFFFB4A0));
  });
}
