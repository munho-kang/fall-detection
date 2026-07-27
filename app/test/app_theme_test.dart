// 밝기 분기 검증 — 이번 버그의 정체가 "분기 누락"이라 빠지면 여기서 바로 실패한다

import 'package:fall_guardian/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final light = buildAppTheme(dark: false, scale: TextScale.normal);
  final dark = buildAppTheme(dark: true, scale: TextScale.normal);

  test('페이지 배경이 밝기별로 다르다', () {
    expect(light.scaffoldBackgroundColor, const Color(0xFFF4F6F6));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF131716));
  });

  test('구분선·컨테이너 색이 밝기별로 다르다', () {
    expect(dark.colorScheme.outlineVariant, isNot(light.colorScheme.outlineVariant));
    expect(dark.colorScheme.primaryContainer, isNot(light.colorScheme.primaryContainer));
    expect(dark.colorScheme.onPrimaryContainer, isNot(light.colorScheme.onPrimaryContainer));
    expect(dark.colorScheme.errorContainer, isNot(light.colorScheme.errorContainer));
    expect(dark.colorScheme.onErrorContainer, isNot(light.colorScheme.onErrorContainer));
  });

  test('라이트 값은 그대로다', () {
    expect(light.colorScheme.outlineVariant, const Color(0xFFC0C9C6));
    expect(light.colorScheme.primaryContainer, const Color(0xFFD3E0DC));
    expect(light.colorScheme.onPrimaryContainer, const Color(0xFF1F3833));
    expect(light.colorScheme.errorContainer, const Color(0xFFFBE3DD));
    expect(light.colorScheme.onErrorContainer, const Color(0xFFD64A2F));
  });

  test('브랜드 색은 양쪽 공통이다', () {
    expect(dark.colorScheme.primary, light.colorScheme.primary);
    expect(dark.colorScheme.onPrimary, light.colorScheme.onPrimary);
    expect(dark.colorScheme.error, light.colorScheme.error);
    expect(dark.colorScheme.outline, light.colorScheme.outline);
  });

  test('dangerColors가 밝기별로 다른 값을 준다', () {
    final l = dangerColors(Brightness.light);
    final d = dangerColors(Brightness.dark);

    expect(l.bg, const Color(0xFFF7DAD2));
    expect(l.fg, const Color(0xFFA03920));
    expect(d.bg, isNot(l.bg));
    expect(d.fg, isNot(l.fg));
  });
}
