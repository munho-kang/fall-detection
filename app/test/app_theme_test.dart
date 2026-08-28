// 라이트 전용 테마 검증 — 다크 분기를 다시 넣거나 팔레트 값이 바뀌면 여기서 바로 실패한다

import 'package:fall_guardian/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = buildAppTheme(scale: TextScale.normal);

  test('테마는 라이트 하나뿐이다', () {
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F6F6));
    expect(theme.appBarTheme.backgroundColor, const Color(0xFFF4F6F6));
  });

  test('라이트 팔레트 값은 그대로다', () {
    expect(theme.colorScheme.outlineVariant, const Color(0xFFC0C9C6));
    expect(theme.colorScheme.primaryContainer, const Color(0xFFD3E0DC));
    expect(theme.colorScheme.onPrimaryContainer, const Color(0xFF1F3833));
    expect(theme.colorScheme.errorContainer, const Color(0xFFFBE3DD));
    expect(theme.colorScheme.onErrorContainer, const Color(0xFFD64A2F));
  });
}
