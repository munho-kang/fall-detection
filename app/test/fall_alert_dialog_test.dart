// 사고 발생 창 — 방·시각 표시, "확인이 유일한 출구", 전화·119 버튼

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// 실패만 돌려주는 페이크 런처 — Windows 호스트의 flutter test는 진짜 런처를 등록할 수
// 있어, 교체하지 않으면 버튼 탭 테스트가 호스트에서 전화 앱을 연다. (dial_test와 같은 이유)
class _FakeUrlLauncher extends UrlLauncherPlatform {
  String? lastUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastUrl = url;
    return false;
  }
}

class _FakeApi extends Api {
  _FakeApi({this.elderPhone = ''});

  final String elderPhone;

  @override
  Future<Profile> getProfile() async => Profile(elderPhone: elderPhone);
}

FallEvent _event({DateTime? reported119At}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 2,
      occurredAt: DateTime(2026, 7, 28, 4, 35),
      createdAt: DateTime(2026, 7, 28, 4, 35),
      confidence: 0.9,
      reported119At: reported119At,
    );

Future<void> _open(
  WidgetTester tester, {
  String elderPhone = '',
  DateTime? reported119At,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(scale: TextScale.normal),
    // 스낵바가 실제로 그려지려면 ScaffoldMessenger에 등록된 Scaffold가 필요하다
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            barrierDismissible: false,
            useRootNavigator: true,
            builder: (_) => FallAlertDialog(
              api: _FakeApi(elderPhone: elderPhone),
              event: _event(reported119At: reported119At),
            ),
          ),
          child: const Text('열기'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

// 라벨로 버튼 위젯을 찾는다 — 활성/비활성(onPressed) 검사용. fall_detail_test와 같은 방식.
Finder _phoneButton() => find.ancestor(
      of: find.text('돌봄 대상자에게 전화'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );

Finder _emergencyButton() => find.ancestor(
      of: find.text('119 긴급 신고'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );

// 스낵바 표시 타이머(기본 4초)를 소진한다 — pending timer로 테스트가 깨지지 않게
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeUrlLauncher launcher;

  setUp(() {
    // 모든 테스트에서 진짜 런처를 차단한다 — 탭 테스트는 실패 경로(스낵바)로 고정된다
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

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

  testWidgets('번호가 등록돼 있으면 전화 버튼이 활성이고 안내문이 없다', (tester) async {
    await _open(tester, elderPhone: '01012345678');

    expect(tester.widget<OutlinedButton>(_phoneButton()).onPressed, isNotNull);
    expect(find.text('프로필에서 전화번호를 등록하면 켜집니다.'), findsNothing);
  });

  testWidgets('번호가 없으면 전화 버튼이 비활성이고 안내문이 보인다', (tester) async {
    await _open(tester);

    expect(tester.widget<OutlinedButton>(_phoneButton()).onPressed, isNull);
    expect(find.text('프로필에서 전화번호를 등록하면 켜집니다.'), findsOneWidget);
  });

  testWidgets('신고 전에는 119 버튼이 활성이고 자동 신고 문구가 없다', (tester) async {
    await _open(tester);

    expect(tester.widget<FilledButton>(_emergencyButton()).onPressed, isNotNull);
    expect(find.text('응답이 없어 119에 자동 신고되었습니다'), findsNothing);
  });

  testWidgets('신고된 이벤트는 119 버튼이 잠기고 자동 신고 문구가 보인다', (tester) async {
    await _open(tester, reported119At: DateTime(2026, 7, 28, 4, 36));

    expect(tester.widget<FilledButton>(_emergencyButton()).onPressed, isNull);
    expect(find.text('응답이 없어 119에 자동 신고되었습니다'), findsOneWidget);
  });

  testWidgets('전화 버튼을 눌러도 창은 유지된다', (tester) async {
    await _open(tester, elderPhone: '01012345678');

    await tester.tap(find.text('돌봄 대상자에게 전화'));
    await tester.pumpAndSettle();

    // 페이크 런처가 실패를 돌려줘 스낵바가 뜨고 창은 남는다
    expect(find.text('사고 발생'), findsOneWidget);
    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);
    expect(launcher.lastUrl, 'tel:01012345678');

    await _drainSnackBar(tester);
  });

  testWidgets('119 버튼을 눌러도 창은 유지된다', (tester) async {
    await _open(tester);

    await tester.tap(find.text('119 긴급 신고'));
    await tester.pumpAndSettle();

    expect(find.text('사고 발생'), findsOneWidget);
    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);
    expect(launcher.lastUrl, 'tel:01000000119');

    await _drainSnackBar(tester);
  });
}
