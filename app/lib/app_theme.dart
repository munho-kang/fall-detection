// 딥 틸 컬러스킴과 라이트/다크 ThemeData, 화면 크기 배율 적용

import 'package:flutter/material.dart';

// screen_v3 컬러 팔레트
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF00695C);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFD3E0DC);
  static const onPrimaryContainer = Color(0xFF1F3833);

  static const surface = Color(0xFFF4F6F6);
  static const surfaceContainer = Color(0xFFFFFFFF);
  static const surfaceContainerHigh = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF191C1B);
  static const onSurfaceVariant = Color(0xFF3F4947);
  static const outline = Color(0xFF6F7977);
  static const outlineVariant = Color(0xFFC0C9C6);

  static const error = Color(0xFFE0563C);
  static const errorContainer = Color(0xFFFBE3DD);
  static const onErrorContainer = Color(0xFFD64A2F);


  static const inverseSurface = Color(0xFF2B3230);
  static const pageBg = Color(0xFFE2E6E6);
}

// 화면 크기 배율 — 작게 0.9 / 보통 1.0 / 크게 1.15
enum TextScale { small, normal, large }

extension TextScaleX on TextScale {
  double get factor {
    switch (this) {
      case TextScale.small:
        return 0.9;
      case TextScale.normal:
        return 1.0;
      case TextScale.large:
        return 1.15;
    }
  }

  String get label {
    switch (this) {
      case TextScale.small:
        return '작게';
      case TextScale.normal:
        return '보통';
      case TextScale.large:
        return '크게';
    }
  }
}

ThemeData buildAppTheme({required bool dark, required TextScale scale}) {
  final base = ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light);
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: dark ? const Color(0xFF1E4640) : AppColors.primaryContainer,
    onPrimaryContainer: dark ? const Color(0xFFB8E7DD) : AppColors.onPrimaryContainer,
    surface: dark ? const Color(0xFF1B1F1E) : AppColors.surface,
    surfaceContainer: dark ? const Color(0xFF222625) : AppColors.surfaceContainer,
    surfaceContainerHigh: dark ? const Color(0xFF222625) : AppColors.surfaceContainerHigh,
    onSurface: dark ? const Color(0xFFE2E6E5) : AppColors.onSurface,
    onSurfaceVariant: dark ? const Color(0xFFBFC9C6) : AppColors.onSurfaceVariant,
    outline: AppColors.outline,
    outlineVariant: dark ? const Color(0xFF3A4442) : AppColors.outlineVariant,
    error: AppColors.error,
    errorContainer: dark ? const Color(0xFF4A241C) : AppColors.errorContainer,
    onErrorContainer: dark ? const Color(0xFFFFB4A0) : AppColors.onErrorContainer,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF131716) : AppColors.surface,
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontSizeFactor: scale.factor,
      fontSizeDelta: 0,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF131716) : AppColors.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

// 파괴적 동작(기록 삭제 · 방 삭제 · 회원 탈퇴) 색 — ColorScheme에 대응 슬롯이 없어 밝기로 직접 고른다.
// BuildContext가 아니라 Brightness를 받으므로 위젯 없이 단위 테스트할 수 있다.
({Color bg, Color fg}) dangerColors(Brightness brightness) => brightness == Brightness.dark
    ? (bg: const Color(0xFF43201A), fg: const Color(0xFFFFB4A0))
    : (bg: const Color(0xFFF7DAD2), fg: const Color(0xFFA03920));
