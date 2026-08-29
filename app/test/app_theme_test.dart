// 라이트 전용 테마 검증 — 다크 분기를 다시 넣거나 컬러 히어로 팔레트 값이 바뀌면 여기서 바로 실패한다.
// 화면 크기 배율이 명시 크기 글자에도 걸리는지도 여기서 지킨다.

import 'package:fall_guardian/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = buildAppTheme();

  test('테마는 라이트 하나뿐이다', () {
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F8FA));
    expect(theme.appBarTheme.backgroundColor, const Color(0xFFF7F8FA));
  });

  test('컬러 히어로 팔레트 값은 그대로다', () {
    expect(theme.colorScheme.primary, const Color(0xFF0E9F6E));
    expect(theme.colorScheme.primaryContainer, const Color(0xFFE3F6EE));
    expect(theme.colorScheme.onPrimaryContainer, const Color(0xFF0A7A55));
    expect(theme.colorScheme.error, const Color(0xFFE5323F));
    expect(theme.colorScheme.errorContainer, const Color(0xFFFDECEE));
    expect(theme.colorScheme.onErrorContainer, const Color(0xFFC9353F));
    expect(theme.colorScheme.outlineVariant, const Color(0xFFF2F4F6));
  });

  test('글꼴은 Pretendard다', () {
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Pretendard');
    expect(theme.appBarTheme.titleTextStyle?.fontFamily, 'Pretendard');
  });

  testWidgets('화면 크기 배율은 명시 크기가 있는 글자에도 걸린다', (tester) async {
    Future<double> heightAt(TextScale scale) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => applyTextScale(context, scale, child!),
        home: const Center(child: Text('가', style: TextStyle(fontSize: 20))),
      ));
      return tester.getSize(find.text('가')).height;
    }

    final normal = await heightAt(TextScale.normal);
    final large = await heightAt(TextScale.large);
    final small = await heightAt(TextScale.small);
    expect(large, closeTo(normal * 1.15, 0.5));
    expect(small, closeTo(normal * 0.9, 0.5));
  });
}
