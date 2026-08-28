// 딥 틸 컬러스킴과 라이트 전용 ThemeData, 화면 크기 배율 적용 — 다크모드는 두지 않는다

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

  // 파괴적 동작(기록 삭제 · 방 삭제 · 회원 탈퇴) 색 — ColorScheme에 대응 슬롯이 없다
  static const dangerBg = Color(0xFFF7DAD2);
  static const dangerFg = Color(0xFFA03920);

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

ThemeData buildAppTheme({required TextScale scale}) {
  final base = ThemeData(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    surface: AppColors.surface,
    surfaceContainer: AppColors.surfaceContainer,
    surfaceContainerHigh: AppColors.surfaceContainerHigh,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    error: AppColors.error,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontSizeFactor: scale.factor,
      fontSizeDelta: 0,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
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
