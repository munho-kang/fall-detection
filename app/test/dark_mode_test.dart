// 다크 테마로 각 화면을 띄워 대표 글자색이 다크 값인지 본다 —
// 라이트 상수가 화면에 하드코딩돼 있으면 여기서 잡힌다

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_detail.dart';
import 'package:fall_guardian/screens/fall_list.dart';
import 'package:fall_guardian/screens/home.dart';
import 'package:fall_guardian/screens/profile.dart';
import 'package:fall_guardian/screens/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class FakeApi extends Api {
  @override
  Future<List<FallEvent>> listFalls() async => const [];

  @override
  Future<Profile> getProfile() async => const Profile(elderPhone: '');
}

final sampleEvent = FallEvent(
  id: 1,
  roomName: '안방',
  roomNumber: 1,
  occurredAt: DateTime(2026, 7, 28, 4, 35),
  createdAt: DateTime(2026, 7, 28, 4, 35),
  confidence: 0.9,
);

void main() {
  // SettingsScreen이 initState에서 LocalStore를 읽는다
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('설정 — 카드 제목이 다크 보조 글자색이다', (tester) async {
    await pumpDark(tester, const SettingsScreen());
    await tester.pump(); // _load()의 비동기 응답

    expect(colorOf(tester, '앱 설정'), darkOnSurfaceVariant);
    expect(colorOf(tester, 'MVP v1.0'), darkOnSurfaceVariant);
  });

  testWidgets('알림 목록 — 타일 시각이 다크 보조 글자색이다', (tester) async {
    await pumpDark(
      tester,
      FallListScreen(
        api: FakeApi(),
        events: [sampleEvent],
        loading: false,
        connectionError: null,
        onLogout: () {},
        onRefresh: () async {},
      ),
    );

    expect(colorOf(tester, '7월 28일 04:35'), darkOnSurfaceVariant);
  });

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

  testWidgets('프로필 — 카드 제목이 다크 보조 글자색, 탈퇴가 다크 danger 색이다', (tester) async {
    await pumpDark(
      tester,
      ProfileScreen(
        api: FakeApi(),
        unreadCount: 0,
        onGoNotifications: () {},
        onGoSettings: () {},
        onLogout: () {},
      ),
    );
    await tester.pump(); // _load()의 비동기 응답

    expect(colorOf(tester, '내 정보'), darkOnSurfaceVariant);

    // 스크롤해서 '회원 탈퇴' 버튼을 보이게 한다
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(colorOf(tester, '회원 탈퇴'), const Color(0xFFFFB4A0));
  });

  testWidgets('낙상 상세 — 라벨이 다크 보조 글자색, 비활성 전화 버튼 글자가 다크 onSurface 계열이다', (tester) async {
    await pumpDark(tester, FallDetailScreen(api: FakeApi(), event: sampleEvent));
    await tester.pump(); // getProfile()의 비동기 응답

    expect(colorOf(tester, '발생 시각'), darkOnSurfaceVariant);

    // 전화번호 미등록이라 비활성이다 — 비활성 글자색이 다크 onSurface의 38%여야 한다
    final phoneButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('돌봄 대상자에게 전화'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(
      phoneButton.style?.foregroundColor?.resolve({WidgetState.disabled}),
      darkOnSurface.withValues(alpha: 0.38),
    );
  });
}
