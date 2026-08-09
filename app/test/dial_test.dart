// 전화 발신 헬퍼 — 전화 앱을 못 여는 환경에서 스낵바로 알리는지

import 'package:fall_guardian/dial.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// 실제 플랫폼 구현 대신 꽂는 페이크 — Windows 호스트에서는 진짜 런처가 등록되므로
// 교체하지 않으면 테스트가 호스트에서 전화 앱을 연다.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({this.result = false, this.throwInstead = false});

  final bool result;
  final bool throwInstead;
  String? lastUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastUrl = url;
    if (throwInstead) throw PlatformException(code: 'launch_failed');
    return result;
  }
}

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => dial(context, '01012345678'),
          child: const Text('걸기'),
        ),
      ),
    ),
  ));
}

// 스낵바 표시 타이머(기본 4초)를 소진한다 — pending timer로 테스트가 깨지지 않게
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('전화 앱을 못 열면 스낵바가 뜬다', (tester) async {
    UrlLauncherPlatform.instance = _FakeUrlLauncher(result: false);
    await _pumpHost(tester);

    await tester.tap(find.text('걸기'));
    await tester.pumpAndSettle();

    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);

    await _drainSnackBar(tester);
  });

  testWidgets('launchUrl이 예외를 던져도 스낵바로 흡수한다', (tester) async {
    UrlLauncherPlatform.instance = _FakeUrlLauncher(throwInstead: true);
    await _pumpHost(tester);

    await tester.tap(find.text('걸기'));
    await tester.pumpAndSettle();

    expect(find.text('전화 앱을 열 수 없습니다.'), findsOneWidget);

    await _drainSnackBar(tester);
  });

  testWidgets('전화 앱이 열리면 tel: 주소로 걸고 스낵바가 없다', (tester) async {
    final launcher = _FakeUrlLauncher(result: true);
    UrlLauncherPlatform.instance = launcher;
    await _pumpHost(tester);

    await tester.tap(find.text('걸기'));
    await tester.pumpAndSettle();

    expect(launcher.lastUrl, 'tel:01012345678');
    expect(find.text('전화 앱을 열 수 없습니다.'), findsNothing);
  });
}
