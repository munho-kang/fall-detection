// 컬러 히어로 팔레트와 라이트 전용 ThemeData, 화면 크기 배율 적용 — 다크모드는 두지 않는다
// 값의 근거: docs/superpowers/specs/2026-08-29-app-visual-redesign-design.md §2·§3·§8

import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const bg = Color(0xFFF7F8FA);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF191F28);
  static const textSub = Color(0xFF6B7684);
  static const textMuted = Color(0xFF8B95A1);
  static const hairline = Color(0xFFF2F4F6);
  static const border = Color(0xFFE5E8EB);

  static const primary = Color(0xFF0E9F6E);
  static const primaryLight = Color(0xFF14B98A);
  static const primaryTint = Color(0xFFE3F6EE);
  static const onPrimaryTint = Color(0xFF0A7A55);
  static const onPrimary = Color(0xFFFFFFFF);

  static const danger = Color(0xFFE5323F);
  static const dangerLight = Color(0xFFF25A66);
  static const dangerTint = Color(0xFFFDECEE);
  static const dangerDeep = Color(0xFFC9353F);

  static const mutedHeroStart = Color(0xFF6B7684);
  static const mutedHeroEnd = Color(0xFF4E5968);

  static const shadow = Color(0x0D000000);

  // ponytail: 화면 태스크(4~10)가 끝나면 지운다 — 옛 화면 코드가 컴파일되게 하는 임시 별칭
  static const error = danger;
  static const errorContainer = dangerTint;
  static const onErrorContainer = dangerDeep;
  static const dangerBg = dangerTint;
  static const dangerFg = dangerDeep;
  static const surface = bg;
  static const surfaceContainer = card;
  static const surfaceContainerHigh = card;
  static const onSurface = text;
  static const onSurfaceVariant = textSub;
  static const outline = border;
  static const outlineVariant = hairline;
  static const primaryContainer = primaryTint;
  static const onPrimaryContainer = onPrimaryTint;
  static const inverseSurface = Color(0xFF2B3230);
  static const pageBg = bg;
}

// 흰 카드 그림자 — AppCard와 카드처럼 보여야 하는 것들이 같이 쓴다
const appShadow = [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 2))];

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

/// 화면 크기 배율을 앱 전체 글자에 건다 — 명시 fontSize가 있는 글자까지 전부 커진다.
/// ThemeData.textTheme.apply(fontSizeFactor:)는 쓰지 않는다: 지역화 전 textTheme엔 fontSize가
/// 없어 디버그에선 assert로 죽고 릴리스에선 아무것도 안 커졌다(app_theme_test가 지킨다).
Widget applyTextScale(BuildContext context, TextScale scale, Widget child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale.factor)),
    child: child,
  );
}

const _font = 'Pretendard';

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, fontFamily: _font);
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryTint,
    onPrimaryContainer: AppColors.onPrimaryTint,
    surface: AppColors.bg,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.card,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textSub,
    outline: AppColors.border,
    outlineVariant: AppColors.hairline,
    error: AppColors.danger,
    onError: AppColors.onPrimary,
    errorContainer: AppColors.dangerTint,
    onErrorContainer: AppColors.dangerDeep,
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const buttonText = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: _font);
  // Material 비활성 알파(배경 12% · 전경 38%)
  final disabledBg = AppColors.text.withValues(alpha: 0.12);
  final disabledFg = AppColors.text.withValues(alpha: 0.38);
  OutlineInputBorder inputBorder(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, fontFamily: _font),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: disabledBg,
        disabledForegroundColor: disabledFg,
        minimumSize: const Size(0, 52),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.text,
        disabledForegroundColor: disabledFg,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 52),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: _font),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.hairline,
      hintStyle: const TextStyle(fontSize: 17, color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: inputBorder(AppColors.hairline, 0),
      enabledBorder: inputBorder(AppColors.hairline, 0),
      focusedBorder: inputBorder(AppColors.primary, 1.5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text, fontFamily: _font),
      contentTextStyle: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSub, fontFamily: _font),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFamily: _font,
          color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.hairline, thickness: 1, space: 1),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.danger, textColor: AppColors.onPrimary),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.text,
      contentTextStyle: const TextStyle(fontSize: 15, color: AppColors.onPrimary, fontFamily: _font),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
  );
}
