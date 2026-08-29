# 앱 디자인 개편(컬러 히어로) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 보호자 Flutter 앱 12개 화면을 "컬러 히어로" 스타일(연회색 바탕 · 흰 카드 · 초록 포인트 · 긴급은 빨간 그라데이션 카드 · Pretendard 글꼴)로 전면 교체하되 기능은 한 줄도 바꾸지 않는다.

**Architecture:** 토큰과 컴포넌트 테마는 `app_theme.dart` 한 곳, 화면들이 공유하는 카드·히어로·칩·타일·버튼은 새 `widgets.dart` 한 곳에 둔다. 화면 파일은 상태 로직(폴링·API 호출·컨트롤러 수명)을 그대로 두고 `build()`만 새 위젯으로 다시 그린다. 기존 테스트가 찾는 문구·위젯 종류(스펙 §1 결정 7 표)는 유지한다.

**Tech Stack:** Flutter 3.44 / Dart ^3.12, Material 3, 새 pub 의존성 없음. 글꼴은 `orioncactus/pretendard` v1.3.9 정적 OTF 3종(자산).

**Spec:** `docs/superpowers/specs/2026-08-29-app-visual-redesign-design.md`

## Global Constraints

- 기능·API·폴링·인증·설정 저장 로직 변경 금지. 라이트 테마 하나뿐(다크 분기 금지). 새 화면·새 패키지 금지.
- `TextScale`(작게 0.9 · 보통 1.0 · 크게 1.15)은 값 유지. 배율은 `buildAppTheme()`가 아니라 `main.dart`의 `MaterialApp.builder`에서 `applyTextScale(context, scale, child)`로 건다(스펙 §8 — 구현 중 발견한 버그 수정).
- 팔레트는 스펙 §2 표의 값을 그대로: bg `#F7F8FA` · card `#FFFFFF` · text `#191F28` · textSub `#6B7684` · textMuted `#8B95A1` · hairline `#F2F4F6` · border `#E5E8EB` · primary `#0E9F6E` · primaryLight `#14B98A` · primaryTint `#E3F6EE` · onPrimaryTint `#0A7A55` · danger `#E5323F` · dangerLight `#F25A66` · dangerTint `#FDECEE` · dangerDeep `#C9353F` · mutedHero `#6B7684→#4E5968` · 그림자 `#000000` 5% blur 10 offset (0,2).
- 모서리: 카드 18 · 히어로 22 · 버튼 14 · 창 24 · 입력칸 14 · 칩 999. 버튼 높이 52(시작 화면 56). 화면 패딩 좌우 20.
- 글꼴 `Pretendard` 400/600/700. 제목 22/700, 섹션·타일 제목·버튼 17/700, 본문 17/400, 보조 15, 칩·탭 13/700.
- 유지할 테스트 문구(스펙 결정 7): `낙상 알림` · `프라이버시 보존형 낙상 감지` · `Icons.shield_outlined` · 시작 화면에 `로그인` 텍스트는 버튼 하나뿐 · `FilledButton`으로 된 `로그인`·`가입하기` · `계정이 없나요? 회원가입` · `사고 발생` · `확인` · `2번` · 방 이름 단독 텍스트 · `7월 28일 04:35` 형식 · `돌봄 대상자에게 전화` · `119 긴급 신고` · `프로필에서 전화번호를 등록하면 켜집니다.` · `응답이 없어 119에 자동 신고되었습니다` · `음성 확인` · `낙상자가 괜찮다고 말했습니다 (yyyy.MM.dd HH:mm)` · `안방 1` · `미확인` · `괜찮다고 말함` · `119 신고됨` · `AlertDialog` 타입(방·프로필 수정 창) · `Icons.edit_outlined` · `방 추가` · `방 수정` · `저장` · `취소` · `닉네임 변경`. 사고 발생 창이 떠 있는 동안 홈에 `확인`·`사고 발생`·`N번` 단독 텍스트가 있으면 안 된다.
- 커밋 메시지는 저장소 관례(`feat:`/`refactor:`/`test:`/`docs:` + 한국어 요약)를 따르고 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` · `Claude-Session: https://claude.ai/code/session_013iyQUwcvBYESCEApFPvZjQ` 두 줄을 붙인다.
- 모든 명령은 `app/` 디렉터리에서 실행한다(`cd /Users/munhokang/82107/fall-detection/app`).

## File Structure

| 파일 | 책임 |
|------|------|
| `app/assets/fonts/Pretendard-{Regular,SemiBold,Bold}.otf`, `LICENSE` | 글꼴 자산(신규) |
| `app/pubspec.yaml` | `flutter.fonts` 등록 |
| `app/lib/app_theme.dart` | `AppColors` 토큰 · `appShadow` · `TextScale` · `buildAppTheme` (전면 교체) |
| `app/lib/widgets.dart` | `AppCard` · `HeroCard`/`HeroTone` · `HeroBackground` · `brandLogo` · `statusLabel` · `StatusChip` · `fmtShort` · `FallTile` · `ActionButton`/`ActionKind` · `NoticeBanner` (신규) |
| `app/lib/screens/splash.dart`, `start.dart` | 초록 그라데이션 첫 화면들 (`brandLogo`는 `widgets.dart`로 이사) |
| `app/lib/screens/login.dart`, `signup.dart` | 본문 큰 제목 + 테마 입력칸 |
| `app/lib/screens/home.dart` | 히어로 · 내 방 · 최근 알림 |
| `app/lib/screens/main_shell.dart` | 하단 탭 위 hairline, 테마에 스타일 위임 |
| `app/lib/screens/fall_list.dart`, `fall_detail.dart` | 카드 목록 · 상태 히어로 + 정보 카드 + `ActionButton` |
| `app/lib/screens/fall_alert_dialog.dart` | `Dialog` + 빨간 히어로 + 정보 상자 + `ActionButton` |
| `app/lib/screens/room_management.dart` | 흰 카드 격자, 힌트 있는 수정 창 |
| `app/lib/screens/profile.dart`, `settings.dart` | `AppCard` 묶음, 세그먼트·배너 |
| `app/test/app_theme_test.dart` | 새 팔레트·글꼴 단언(갱신) |
| `app/test/widgets_test.dart` | 상태 문구·시각 형식·타일·버튼 비활성(신규) |
| `README.md`, `docs/screenshots/01~14` | 문서·스크린샷 갱신 |

---

### Task 1: Pretendard 글꼴 자산 등록

**Files:**
- Create: `app/assets/fonts/Pretendard-Regular.otf`, `Pretendard-SemiBold.otf`, `Pretendard-Bold.otf`, `app/assets/fonts/LICENSE`
- Modify: `app/pubspec.yaml` (`flutter:` 절)

**Interfaces:**
- Produces: 글꼴 패밀리 이름 `'Pretendard'` (Task 2의 `ThemeData(fontFamily:)`가 쓴다)

- [ ] **Step 1: 글꼴 3종과 라이선스 내려받기**

```bash
cd /Users/munhokang/82107/fall-detection/app && mkdir -p assets/fonts && cd assets/fonts
B=https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9
for w in Regular SemiBold Bold; do curl -sSL -o Pretendard-$w.otf "$B/packages/pretendard/dist/public/static/Pretendard-$w.otf"; done
curl -sSL -o LICENSE "$B/LICENSE"
ls -la && file Pretendard-Regular.otf
```
Expected: 세 OTF 각 약 1.5 MB, `file`이 `OpenType font data`라고 답한다. LICENSE 첫 줄에 `SIL Open Font License`.

- [ ] **Step 2: pubspec.yaml에 등록**

`app/pubspec.yaml`의 `flutter:` 절 안 `uses-material-design: true` 아래에 추가(주석 블록은 지워도 된다):

```yaml
  fonts:
    - family: Pretendard
      fonts:
        - asset: assets/fonts/Pretendard-Regular.otf
          weight: 400
        - asset: assets/fonts/Pretendard-SemiBold.otf
          weight: 600
        - asset: assets/fonts/Pretendard-Bold.otf
          weight: 700
```

- [ ] **Step 3: 자산이 잡히는지 확인**

Run: `cd /Users/munhokang/82107/fall-detection/app && flutter pub get && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/pubspec.yaml app/assets/fonts && git commit -m "feat: Pretendard 글꼴 3종(400·600·700) 자산 등록"
```

---

### Task 2: 팔레트·테마 전면 교체 (`app_theme.dart`)

**Files:**
- Modify: `app/lib/app_theme.dart` (전체 교체)
- Test: `app/test/app_theme_test.dart` (전체 교체)

**Interfaces:**
- Consumes: 글꼴 패밀리 `'Pretendard'` (Task 1)
- Produces: `AppColors.{bg,card,text,textSub,textMuted,hairline,border,primary,primaryLight,primaryTint,onPrimaryTint,danger,dangerLight,dangerTint,dangerDeep,mutedHeroStart,mutedHeroEnd,onPrimary,shadow}`, `const List<BoxShadow> appShadow`, `enum TextScale` + `factor`/`label`, `ThemeData buildAppTheme({required TextScale scale})`

- [ ] **Step 1: 테스트를 새 값으로 바꾼다 (실패 확인용)**

`app/test/app_theme_test.dart` 전체:

```dart
// 라이트 전용 테마 검증 — 다크 분기를 다시 넣거나 컬러 히어로 팔레트 값이 바뀌면 여기서 바로 실패한다

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

  test('화면 크기 배율이 글자 크기에 곱해진다', () {
    final large = buildAppTheme(scale: TextScale.large);
    expect(large.textTheme.bodyMedium!.fontSize, closeTo(theme.textTheme.bodyMedium!.fontSize! * 1.15, 0.01));
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/app_theme_test.dart`
Expected: 팔레트·글꼴 테스트 FAIL (옛 값 `0xFFF4F6F6` 등이 나온다).

- [ ] **Step 3: `app_theme.dart` 전체 교체**

```dart
// 컬러 히어로 팔레트와 라이트 전용 ThemeData, 화면 크기 배율 적용 — 다크모드는 두지 않는다
// 값의 근거: docs/superpowers/specs/2026-08-29-app-visual-redesign-design.md §2·§3

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

const _font = 'Pretendard';

ThemeData buildAppTheme({required TextScale scale}) {
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
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontSizeFactor: scale.factor,
      fontSizeDelta: 0,
    ),
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
```

- [ ] **Step 4: 테마 테스트 통과 확인**

Run: `flutter test test/app_theme_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 5: 옛 이름을 쓰던 곳을 찾아 임시로 통과시키지 않는다 — 컴파일 깨짐 목록만 적어 둔다**

Run: `flutter analyze 2>&1 | grep -c "isn't defined"`
Expected: `AppColors.error`·`errorContainer`·`onErrorContainer`·`dangerBg`·`dangerFg`·`surface`·`primaryContainer`·`onPrimaryContainer`·`onSurface` 등 옛 멤버 참조 오류가 여러 개 나온다. 화면 태스크(4~10)가 파일마다 없앤다. 이 시점에 커밋하지 않는다 — Task 3까지 묶어서 `analyze`가 깨진 채로 두는 대신, 아래 Step 6으로 옛 이름을 잠시 살려 둔다.

- [ ] **Step 6: 옛 이름 호환 별칭을 잠시 둔다 (화면 태스크가 끝나면 지운다)**

`AppColors` 클래스 끝, `shadow` 아래에 추가:

```dart
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
```

Run: `flutter analyze && flutter test`
Expected: analyze 깨끗, 기존 테스트 전부 PASS(화면은 아직 옛 모양이지만 새 색으로 그려진다).

- [ ] **Step 7: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/lib/app_theme.dart app/test/app_theme_test.dart && git commit -m "feat: 컬러 히어로 팔레트·컴포넌트 테마로 app_theme 교체, Pretendard 적용"
```

---

### Task 3: 공통 위젯 (`widgets.dart`)

**Files:**
- Create: `app/lib/widgets.dart`
- Test: `app/test/widgets_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `appShadow` (Task 2); `FallEvent`(`roomLabel`, `occurredAt`, `isAcknowledged`, `isReported119`, `isVoiceOk`) from `lib/models.dart`
- Produces:
  - `class AppCard({required Widget child, EdgeInsetsGeometry padding = EdgeInsets.all(16), VoidCallback? onTap})`
  - `enum HeroTone { safe, alert, muted }` · `class HeroCard({required HeroTone tone, required Widget child, EdgeInsetsGeometry padding = EdgeInsets.all(20)})`
  - `class HeroBackground({required Widget child, BorderRadius? borderRadius})` — 화면을 채우는 초록 그라데이션
  - `Widget brandLogo({double size = 120})`
  - `String statusLabel(FallEvent e)` · `class StatusChip({required FallEvent event})`
  - `String fmtShort(DateTime t)` → `'8월 4일 21:07'`
  - `class FallTile({required FallEvent event, required VoidCallback onTap})`
  - `enum ActionKind { primary, outlined, emergency, destructive }` · `class ActionButton({required String label, required ActionKind kind, IconData? icon, required VoidCallback? onPressed})`
  - `class NoticeBanner({required String text})` — 연한 붉은 경고 배너

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/widgets_test.dart`:

```dart
// 공통 위젯 — 상태 문구 우선순위 · 시각 형식 · 타일 구성 · 동작 버튼 비활성

import 'package:fall_guardian/app_theme.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent _event({DateTime? ack, DateTime? r119, DateTime? ok}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 8, 4, 21, 7),
      createdAt: DateTime(2026, 8, 4, 21, 7),
      confidence: 0.9,
      acknowledgedAt: ack,
      reported119At: r119,
      voiceOkAt: ok,
    );

void main() {
  final t = DateTime(2026, 8, 5);

  test('상태 문구 — 119 신고됨 > 괜찮다고 말함 > 확인함/미확인', () {
    expect(statusLabel(_event()), '미확인');
    expect(statusLabel(_event(ack: t)), '확인함');
    expect(statusLabel(_event(ack: t, ok: t)), '괜찮다고 말함');
    expect(statusLabel(_event(ok: t, r119: t)), '119 신고됨');
  });

  test('짧은 시각 형식은 월 일 시:분', () {
    expect(fmtShort(DateTime(2026, 8, 4, 21, 7)), '8월 4일 21:07');
  });

  testWidgets('타일은 방 이름·시각·상태 칩을 그린다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: FallTile(event: _event(ok: t), onTap: () {})),
    ));
    expect(find.text('안방 1'), findsOneWidget);
    expect(find.text('8월 4일 21:07'), findsOneWidget);
    expect(find.text('괜찮다고 말함'), findsOneWidget);
  });

  testWidgets('동작 버튼은 onPressed가 없으면 눌리지 않는다', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [
          ActionButton(label: '켜짐', kind: ActionKind.emergency, onPressed: () => pressed++),
          const ActionButton(label: '꺼짐', kind: ActionKind.emergency, onPressed: null),
        ]),
      ),
    ));
    await tester.tap(find.text('켜짐'));
    await tester.tap(find.text('꺼짐'));
    expect(pressed, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '꺼짐')).enabled, isFalse);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/widgets_test.dart`
Expected: 컴파일 오류 — `package:fall_guardian/widgets.dart` 없음.

- [ ] **Step 3: `widgets.dart` 작성**

```dart
// 공통 위젯 — 흰 카드 · 그라데이션 히어로 · 상태 칩 · 알림 타일 · 동작 버튼 · 경고 배너.
// 화면마다 복붙돼 있던 카드·타일·버튼·상태 문구 로직을 여기 한 곳에 모은다

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'models.dart';

/// 흰 카드 — 모서리 18, 은은한 그림자. onTap이 있으면 잉크 효과.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: radius, boxShadow: appShadow),
      // ListTile·InkWell은 가장 가까운 Material에 그린다 — Container만으로 감싸면 디버그 검증이 예외를 던진다
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

enum HeroTone { safe, alert, muted }

const _heroColors = {
  HeroTone.safe: [AppColors.primaryLight, AppColors.primary],
  HeroTone.alert: [AppColors.dangerLight, AppColors.danger],
  HeroTone.muted: [AppColors.mutedHeroStart, AppColors.mutedHeroEnd],
};

Widget _bubble(double size, double opacity) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.onPrimary.withValues(alpha: opacity)),
    );

/// 그라데이션 카드 — 톤별 색, 장식 원 둘, 안의 글씨·아이콘은 기본 흰색
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.tone, required this.child, this.padding = const EdgeInsets.all(20)});

  final HeroTone tone;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _heroColors[tone]!),
      ),
      child: Stack(
        children: [
          Positioned(right: -24, top: -24, child: _bubble(120, 0.12)),
          Positioned(right: 20, bottom: -40, child: _bubble(90, 0.08)),
          Padding(
            padding: padding,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: AppColors.onPrimary),
              child: IconTheme.merge(data: const IconThemeData(color: AppColors.onPrimary), child: child),
            ),
          ),
        ],
      ),
    );
  }
}

/// 화면(또는 상단 영역)을 채우는 초록 그라데이션 — 스플래시·시작 화면
class HeroBackground extends StatelessWidget {
  const HeroBackground({super.key, required this.child, this.borderRadius});

  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primary],
        ),
      ),
      child: Stack(
        children: [
          Positioned(right: -50, top: -30, child: _bubble(190, 0.10)),
          Positioned(left: -40, bottom: -60, child: _bubble(150, 0.08)),
          child,
        ],
      ),
    );
  }
}

/// 로고 상자 — 그라데이션 위에 놓이는 흰 20% 네모 + 방패. 스플래시 120, 시작 화면 72
Widget brandLogo({double size = 120}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(Icons.shield_outlined, size: size / 2, color: AppColors.onPrimary),
    );

/// 상태 문구 우선순위 — 119 신고됨 > 괜찮다고 말함 > 확인함/미확인. 안전 쪽이 이긴다
String statusLabel(FallEvent e) {
  if (e.isReported119) return '119 신고됨';
  if (e.isVoiceOk) return '괜찮다고 말함';
  return e.isAcknowledged ? '확인함' : '미확인';
}

/// 상태 칩 — 문구별 배경/글씨
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.event});

  final FallEvent event;

  @override
  Widget build(BuildContext context) {
    final label = statusLabel(event);
    final (bg, fg) = switch (label) {
      '괜찮다고 말함' => (AppColors.primaryTint, AppColors.onPrimaryTint),
      '확인함' => (AppColors.hairline, AppColors.textSub),
      _ => (AppColors.dangerTint, AppColors.danger), // 119 신고됨 · 미확인
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// '8월 4일 21:07' — 홈 · 알림 목록 · 사고 발생 창 공용
String fmtShort(DateTime t) =>
    '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 알림 한 줄 — 방 이름 · 시각 · 상태 칩
class FallTile extends StatelessWidget {
  const FallTile({super.key, required this.event, required this.onTap});

  final FallEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.roomLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(fmtShort(event.occurredAt), style: const TextStyle(fontSize: 15, color: AppColors.textSub)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusChip(event: event),
          ],
        ),
      ),
    );
  }
}

enum ActionKind { primary, outlined, emergency, destructive }

/// 동작 버튼 — 높이 52 · 모서리 14 · 17/700은 테마가 준다. onPressed가 null이면 비활성
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.kind, this.icon, required this.onPressed});

  final String label;
  final ActionKind kind;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Text(label),
      ],
    );
    // FilledButton.styleFrom은 disabled 색을 안 주면 enabled 색을 비활성에도 쓴다 — 반드시 같이 준다
    final disabledBg = AppColors.text.withValues(alpha: 0.12);
    final disabledFg = AppColors.text.withValues(alpha: 0.38);
    switch (kind) {
      case ActionKind.primary:
        return FilledButton(onPressed: onPressed, child: child);
      case ActionKind.outlined:
        return OutlinedButton(onPressed: onPressed, child: child);
      case ActionKind.emergency:
        return FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: disabledBg,
            disabledForegroundColor: disabledFg,
          ),
          child: child,
        );
      case ActionKind.destructive:
        return FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.dangerTint,
            foregroundColor: AppColors.dangerDeep,
            disabledBackgroundColor: AppColors.dangerTint.withValues(alpha: 0.4),
            disabledForegroundColor: AppColors.dangerDeep.withValues(alpha: 0.38),
          ),
          child: child,
        );
    }
  }
}

/// 연한 붉은 경고 배너 — 연결 끊김 · 알림 끔 안내
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.dangerTint, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.dangerDeep),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.dangerDeep))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/widgets_test.dart && flutter analyze`
Expected: 4 tests PASS, analyze 깨끗.

- [ ] **Step 5: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/lib/widgets.dart app/test/widgets_test.dart && git commit -m "feat: 공통 위젯 — AppCard·HeroCard·StatusChip·FallTile·ActionButton·NoticeBanner"
```

---

### Task 4: 스플래시·시작 화면

**Files:**
- Modify: `app/lib/screens/splash.dart` (전체 교체 — `brandLogo`는 `widgets.dart`로 이사했으므로 여기서 삭제)
- Modify: `app/lib/screens/start.dart` (전체 교체)
- Test: 기존 `app/test/splash_test.dart`, `app/test/login_test.dart`

**Interfaces:**
- Consumes: `HeroBackground`, `brandLogo(size:)` (Task 3); `AppColors` (Task 2)
- Produces: 없음(화면 시그니처 `SplashScreen({api, onDone})`, `StartScreen({api})` 유지)

- [ ] **Step 1: 기존 테스트가 통과하는지 먼저 본다(기준선)**

Run: `flutter test test/splash_test.dart test/login_test.dart`
Expected: PASS.

- [ ] **Step 2: `splash.dart` 전체 교체**

```dart
// 스플래시 화면 — 초록 그라데이션 배경에 로고, 1~2초 후 토큰 판단 결과로 분기

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../widgets.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.api, required this.onDone});

  final Api api;
  // 토큰 판단 후 호출. true면 로그인 됨, false면 시작 화면으로.
  final void Function(bool loggedIn) onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 최소 1.2초 노출 → 로고가 한 번 읽히도록. 동시에 토큰을 읽는다.
    const minDelay = Duration(milliseconds: 1200);
    final results = await Future.wait<dynamic>([widget.api.loadToken(), Future.delayed(minDelay)]);
    final token = results[0] as String?;
    if (!mounted) return;
    widget.onDone(token != null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HeroBackground(
        child: SafeArea(
          // Scaffold body는 가로 constraints를 느슨하게 준다 — 기본 center 정렬만 믿으면
          // Column이 가장 넓은 자식 폭으로 수축해 화면 왼쪽에 붙는다. stretch + textAlign 조합으로 폭을 채운다.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(child: brandLogo()),
              const SizedBox(height: 24),
              const Text(
                '낙상 알림',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: -0.5,
                  color: AppColors.onPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '프라이버시 보존형 낙상 감지',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xCCFFFFFF)),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: `start.dart` 전체 교체**

```dart
// 시작 화면 — 초록 히어로(로고 · 소개) 위, 로그인/회원가입 버튼 아래. 신규·로그인 진입의 첫 화면

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../widgets.dart';
import 'login.dart';
import 'signup.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.api});

  final Api api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 위: 남는 높이를 전부 차지하는 초록 히어로
          Expanded(
            child: HeroBackground(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      brandLogo(size: 72),
                      const SizedBox(height: 18),
                      const Text(
                        '낙상 알림',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: -0.5,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '돌봄 대상자의 낙상을 감지해\n보호자에게 실시간으로 알려드립니다.',
                        style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xEBFFFFFF)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 아래: 버튼 둘 + 사생활 한 줄. 자연 높이만 차지한다
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // tall 버튼(56dp). 손이 큰 사용자도 정확히 누르도록
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LoginScreen(api: api)),
                      ),
                      child: const Text('로그인'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SignupScreen(api: api)),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primaryTint, width: 1.5),
                      ),
                      child: const Text('회원가입'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
                      SizedBox(width: 5),
                      Text('영상은 집 밖으로 나가지 않아요', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 통과 확인**

Run: `flutter analyze && flutter test test/splash_test.dart test/login_test.dart`
Expected: analyze 깨끗, PASS. (`splash_test`는 로고·제목·부제가 가로 중앙인지 본다 — `Center`와 `textAlign: center`가 지킨다.)

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/splash.dart app/lib/screens/start.dart && git commit -m "feat: 스플래시·시작 화면을 초록 히어로 스타일로"
```

---

### Task 5: 로그인·회원가입 화면

**Files:**
- Modify: `app/lib/screens/login.dart` (전체 교체)
- Modify: `app/lib/screens/signup.dart` (전체 교체)
- Test: 기존 `app/test/login_test.dart`

**Interfaces:**
- Consumes: `AppColors` (Task 2). 입력칸·버튼 모양은 Task 2의 `inputDecorationTheme`·`filledButtonTheme`이 준다.
- Produces: 없음(`LoginScreen({api})`, `SignupScreen({api})` 유지, `pushAndRemoveUntil` 유지)

- [ ] **Step 1: `login.dart` 전체 교체**

```dart
// 보호자 로그인 화면 — 시작 화면에서 진입. 본문 큰 제목 + 입력칸 두 개 + 버튼

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import 'main_shell.dart';
import 'signup.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});

  final Api api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.login(_username.text, _password.text);
      if (!mounted) return;
      // 스택을 전부 걷어낸다 — pushReplacement는 이 로그인 라우트만 바꿔서 아래의
      // 시작 화면이 남고, 로그인된 홈에 뒤로가기 화살표가 생긴다. 회원가입과 같은 방식.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainShell(api: widget.api)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('로그인', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              const Text('보호자 계정으로 들어가요', style: TextStyle(fontSize: 15, color: AppColors.textSub)),
              const SizedBox(height: 28),
              TextField(
                controller: _username,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '아이디'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '비밀번호'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Text('로그인'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SignupScreen(api: widget.api)),
                        ),
                child: const Text('계정이 없나요? 회원가입'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: `signup.dart` 전체 교체**

```dart
// 보호자 회원가입 화면 — 가입 성공 시 바로 MainShell로 들어간다

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import 'main_shell.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.api});

  final Api api;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text != _confirm.text) {
      setState(() => _error = '비밀번호가 서로 다릅니다.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.signup(_username.text, _password.text);
      if (!mounted) return;
      // 로그인 화면까지 스택에서 걷어내 뒤로 가기로 되돌아가지 않게 한다
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainShell(api: widget.api)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('회원가입', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              // 규칙 안내 — 칸 위에 두어 다 치고 나서 읽는 경고가 아니라 치기 전 읽는 안내
              const Text(
                '비밀번호는 영문자, 숫자, 특수기호를 섞어 8자 이상으로 만들어주세요.',
                style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSub),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _username,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '아이디'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '비밀번호'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '비밀번호 확인'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Text('가입하기'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 통과 확인**

Run: `flutter analyze && flutter test test/login_test.dart`
Expected: analyze 깨끗, PASS(`FilledButton`으로 된 `로그인`·`가입하기`, `TextField` 순서 유지).

- [ ] **Step 4: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/lib/screens/login.dart app/lib/screens/signup.dart && git commit -m "feat: 로그인·회원가입을 본문 큰 제목 + 테마 입력칸으로"
```

---

### Task 6: 홈 화면과 하단 탭

**Files:**
- Modify: `app/lib/screens/home.dart` (전체 교체)
- Modify: `app/lib/screens/main_shell.dart` (`bottomNavigationBar:` 부분과 import)
- Test: 기존 `app/test/main_shell_alert_test.dart` + `app/test/widgets_test.dart`에 홈 히어로 테스트 3건 추가

**Interfaces:**
- Consumes: `AppCard`, `HeroCard`/`HeroTone`, `FallTile`, `fmtShort` (Task 3); `AppColors`, `appShadow` (Task 2); `Room.label` (`'거실 1'`)
- Produces: 없음(`HomeScreen` 생성자 파라미터 그대로 — `main_shell.dart` 호출부 불변)

- [ ] **Step 1: 히어로 상태 테스트를 `widgets_test.dart` 끝(`main`의 닫는 `}` 앞)에 추가**

```dart
  group('홈 히어로', () {
    Widget home({List<FallEvent> events = const [], String? error, bool loading = false}) => MaterialApp(
          theme: buildAppTheme(),
          home: HomeScreen(
            events: events,
            rooms: const [],
            loadingEvents: loading,
            loadingRooms: false,
            connectionError: error,
            unreadCount: events.where((e) => !e.isAcknowledged).length,
            onGoNotifications: () {},
            onGoSettings: () {},
            onChangeTab: (_) {},
            api: Api(),
            onLogout: () {},
          ),
        );

    testWidgets('미확인이 없으면 초록 안전 카드', (tester) async {
      await tester.pumpWidget(home(events: [_event(ack: t)]));
      expect(find.text('지금은 안전해요'), findsOneWidget);
      expect(find.text('아직 등록한 방이 없어요'), findsOneWidget);
    });

    testWidgets('미확인이 있으면 빨간 카드에 건수와 확인하기 버튼', (tester) async {
      await tester.pumpWidget(home(events: [_event(), _event(ack: t)]));
      expect(find.text('미확인 낙상 1건'), findsOneWidget);
      expect(find.text('확인하기'), findsOneWidget);
      expect(find.text('지금은 안전해요'), findsNothing);
    });

    testWidgets('연결이 끊기면 회색 카드에 오류 문구', (tester) async {
      await tester.pumpWidget(home(error: '서버와 연결이 끊겼습니다.'));
      expect(find.text('서버와 연결이 끊겼습니다.'), findsOneWidget);
      expect(find.text('지금은 안전해요'), findsNothing);
    });
  });
```

파일 상단 import에 추가: `import 'package:fall_guardian/api.dart';` · `import 'package:fall_guardian/screens/home.dart';`

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/widgets_test.dart`
Expected: 홈 히어로 3건 FAIL(옛 홈에는 `지금은 안전해요`가 없다).

- [ ] **Step 3: `home.dart` 전체 교체**

```dart
// 홈 화면 (메인) — 상단 바(알림 · 설정) + 상태 히어로 + 내 방 + 최근 알림

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'fall_detail.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.events,
    required this.rooms,
    required this.loadingEvents,
    required this.loadingRooms,
    required this.connectionError,
    required this.unreadCount,
    required this.onGoNotifications,
    required this.onGoSettings,
    required this.onChangeTab,
    required this.api,
    required this.onLogout,
  });

  final List<FallEvent> events;
  final List<Room> rooms;
  final bool loadingEvents;
  final bool loadingRooms;
  final String? connectionError;
  final int unreadCount;
  final VoidCallback onGoNotifications;
  final VoidCallback onGoSettings;
  final ValueChanged<int> onChangeTab;
  final Api api;
  final VoidCallback onLogout;

  static const _heroTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.25);
  static const _heroSub = TextStyle(fontSize: 14, color: Color(0xE6FFFFFF));
  static const _sectionTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final unread = events.where((e) => !e.isAcknowledged).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('낙상 알림'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: onGoNotifications,
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: onGoSettings),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _hero(context, unread),
          const SizedBox(height: 12),
          _roomsCard(),
          const SizedBox(height: 24),
          const Text('최근 알림', style: _sectionTitle),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: loadingEvents
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : events.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text('아직 감지된 낙상이 없어요.', style: TextStyle(fontSize: 15, color: AppColors.textSub)),
                        ),
                      )
                    : Column(
                        children: [
                          for (int i = 0; i < events.length; i++) ...[
                            FallTile(event: events[i], onTap: () => _open(context, events[i])),
                            if (i < events.length - 1) const Divider(),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // 상태 히어로 — 미확인 > 연결 끊김 > 로딩 > 안전. 놓치면 안 되는 쪽이 이긴다
  Widget _hero(BuildContext context, List<FallEvent> unread) {
    if (unread.isNotEmpty) {
      final latest = unread.first; // 서버가 최신순으로 준다
      return HeroCard(
        tone: HeroTone.alert,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kicker(Icons.warning_amber_rounded, '낙상 감지'),
            const SizedBox(height: 10),
            Text('미확인 낙상 ${unread.length}건', style: _heroTitle),
            const SizedBox(height: 4),
            Text('${latest.roomLabel} · ${fmtShort(latest.occurredAt)}', style: _heroSub),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => _open(context, latest),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.card,
                  foregroundColor: AppColors.danger,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: const Text('확인하기'),
              ),
            ),
          ],
        ),
      );
    }
    if (connectionError != null) {
      return HeroCard(
        tone: HeroTone.muted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kicker(Icons.wifi_off_rounded, '연결 끊김'),
            const SizedBox(height: 10),
            Text(connectionError!, style: _heroTitle),
            const SizedBox(height: 4),
            const Text('연결되면 자동으로 다시 확인해요', style: _heroSub),
          ],
        ),
      );
    }
    if (loadingEvents) {
      return HeroCard(
        tone: HeroTone.muted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kicker(Icons.sync_rounded, '연결 중'),
            const SizedBox(height: 10),
            const Text('불러오는 중…', style: _heroTitle),
          ],
        ),
      );
    }
    return HeroCard(
      tone: HeroTone.safe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kicker(Icons.check_circle_rounded, '실시간 감지 중'),
          const SizedBox(height: 10),
          const Text('지금은 안전해요', style: _heroTitle),
          const SizedBox(height: 4),
          Text('미확인 알림 0건 · 방 ${rooms.length}개 연결됨', style: _heroSub),
        ],
      ),
    );
  }

  Widget _kicker(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      );

  // 내 방 — 카드 전체와 '+ 방 추가'가 방 관리 탭으로 보낸다
  Widget _roomsCard() => AppCard(
        onTap: () => onChangeTab(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(child: Text('내 방', style: _sectionTitle)),
                Text('+ 방 추가', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 12),
            if (loadingRooms)
              const Text('불러오는 중…', style: TextStyle(fontSize: 15, color: AppColors.textSub))
            else if (rooms.isEmpty)
              const Text('아직 등록한 방이 없어요', style: TextStyle(fontSize: 15, color: AppColors.textSub))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in rooms)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(999)),
                      child: Text(r.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSub)),
                    ),
                ],
              ),
          ],
        ),
      );

  Future<void> _open(BuildContext context, FallEvent e) async {
    await Navigator.of(context).push<FallEvent>(
      MaterialPageRoute(builder: (_) => FallDetailScreen(api: api, event: e)),
    );
    // 홈에서는 별도 갱신 로직 없음 — MainShell의 폴러가 다음 틱에 반영
  }
}
```

- [ ] **Step 4: `main_shell.dart` 하단 탭 교체**

import에 `import '../app_theme.dart';`를 추가하고, `bottomNavigationBar: NavigationBar(...)` 블록 전체를 다음으로 바꾼다(목적지 세 개는 그대로):

```dart
      bottomNavigationBar: Container(
        // 모양(흰 배경 · 높이 72 · 활성 초록)은 navigationBarTheme이 준다. 위 hairline만 여기서
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.hairline))),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              selectedIcon: Icon(Icons.home),
              icon: Icon(Icons.home_outlined),
              label: '홈',
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.grid_view),
              icon: Icon(Icons.grid_view_outlined),
              label: '방 관리',
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.person),
              icon: Icon(Icons.person_outline),
              label: '프로필',
            ),
          ],
        ),
      ),
```

- [ ] **Step 5: 통과 확인**

Run: `flutter analyze && flutter test test/widgets_test.dart test/main_shell_alert_test.dart`
Expected: analyze 깨끗, 전부 PASS. `main_shell_alert_test`는 창이 떠 있을 때 `확인`·`사고 발생`·`2번`이 하나씩만 있어야 한다 — 홈에는 `확인하기`·`낙상 감지`·`안방 2 · …`처럼 다른 문자열만 있다.

- [ ] **Step 6: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/lib/screens/home.dart app/lib/screens/main_shell.dart app/test/widgets_test.dart && git commit -m "feat: 홈을 상태 히어로·내 방·최근 알림으로 재구성, 하단 탭 테마 위임"
```

---

### Task 7: 알림 목록·알림 상세

**Files:**
- Modify: `app/lib/screens/fall_list.dart` (`build` 교체, `_fmt`·`_alertTile` 삭제, `_open` 추가)
- Modify: `app/lib/screens/fall_detail.dart` (`build`·`_row` 교체, `_actionButton` 삭제, `_delete` 창 버튼 색)
- Test: 기존 `app/test/fall_list_test.dart`, `app/test/fall_detail_test.dart`

**Interfaces:**
- Consumes: `AppCard`, `HeroCard`/`HeroTone`, `FallTile`, `NoticeBanner`, `statusLabel`, `ActionButton`/`ActionKind` (Task 3); `dial`·`emergencyPhone` (`lib/dial.dart`)
- Produces: 없음(화면 시그니처·상태 로직·`Navigator.pop(_event)` 반환 유지)

- [ ] **Step 1: 기준선**

Run: `flutter test test/fall_list_test.dart test/fall_detail_test.dart`
Expected: PASS.

- [ ] **Step 2: `fall_list.dart` — import를 아래로 바꾸고, `_fmt`와 `_alertTile`을 지우고, `build`를 교체한다**

import 블록:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'fall_detail.dart';
```

`build`와 새 `_open` (클래스 안 `_refresh` 아래에 둔다):

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('알림'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (_error != null) ...[
              NoticeBanner(text: _error!),
              const SizedBox(height: 16),
            ],
            if (_events.isEmpty)
              const SizedBox(
                height: 400,
                child: Center(
                  child: Text('아직 감지된 낙상이 없어요.', style: TextStyle(fontSize: 15, color: AppColors.textSub)),
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (int i = 0; i < _events.length; i++) ...[
                      FallTile(event: _events[i], onTap: () => _open(_events[i])),
                      if (i < _events.length - 1) const Divider(),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(FallEvent e) async {
    await Navigator.of(context).push<FallEvent>(
      MaterialPageRoute(builder: (_) => FallDetailScreen(api: widget.api, event: e)),
    );
    // 돌아오면 MainShell 폴러가 곧 반영하지만, 즉시 새로고침 트리거
    await _refresh();
  }
```

- [ ] **Step 3: `fall_detail.dart` — import를 바꾸고 `build`·`_row`를 교체, `_actionButton`을 지운다**

import 블록(`app_theme.dart`의 `show AppColors`를 없앤다):

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../dial.dart';
import '../models.dart';
import '../widgets.dart';
```

`_delete` 안 확인 창의 `삭제` 버튼을 붉은 글씨로:

```dart
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerDeep),
            child: const Text('삭제'),
          ),
```

`build`와 `_row`:

```dart
  @override
  Widget build(BuildContext context) {
    final phoneRegistered = _elderPhone != null && _elderPhone!.isNotEmpty;
    final label = statusLabel(_event);
    // 히어로 톤은 칩 문구를 따른다 — 괜찮다고 말함=초록, 확인함=회색, 미확인·119 신고됨=빨강
    final tone = switch (label) {
      '괜찮다고 말함' => HeroTone.safe,
      '확인함' => HeroTone.muted,
      _ => HeroTone.alert,
    };
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop(_event)),
        title: const Text('알림'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          HeroCard(
            tone: tone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                Text(
                  _event.roomLabel,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Text(_fmt(_event.occurredAt), style: const TextStyle(fontSize: 13, color: Color(0xE6FFFFFF))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 정보 카드
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                _row('발생 시각', _fmt(_event.occurredAt)),
                _row(
                  '감지 신뢰도',
                  '${(_event.confidence * 100).toStringAsFixed(0)}%',
                  valueColor: AppColors.primary,
                ),
                _row(
                  '현재 상태',
                  _event.isAcknowledged ? '확인함 (${_fmt(_event.acknowledgedAt!)})' : '미확인',
                  valueColor: _event.isAcknowledged ? AppColors.textSub : AppColors.danger,
                ),
                if (_event.isVoiceOk)
                  _row(
                    '음성 확인',
                    '낙상자가 괜찮다고 말했습니다 (${_fmt(_event.voiceOkAt!)})',
                    valueColor: AppColors.primary,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 알림 확인 버튼 — 확인 완료 시 비활성
          ActionButton(
            label: '알림 확인',
            icon: Icons.check,
            kind: ActionKind.primary,
            onPressed: (!_busy && !_event.isAcknowledged) ? _acknowledge : null,
          ),
          const SizedBox(height: 12),
          // 돌봄 대상자에게 전화 — 미등록이면 비활성 + 안내
          ActionButton(
            label: '돌봄 대상자에게 전화',
            icon: Icons.phone,
            kind: ActionKind.outlined,
            onPressed: phoneRegistered ? () => dial(context, _elderPhone!) : null,
          ),
          if (!phoneRegistered) ...[
            const SizedBox(height: 8),
            const Text(
              '프로필에서 전화번호를 등록하면 켜집니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.textSub),
            ),
          ],
          const SizedBox(height: 12),
          // 119 긴급 신고 — 이미 자동 신고된 이벤트면 잠근다
          ActionButton(
            label: '119 긴급 신고',
            icon: Icons.warning_amber,
            kind: ActionKind.emergency,
            onPressed: _event.isReported119 ? null : () => dial(context, emergencyPhone),
          ),
          if (_event.isReported119)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '응답이 없어 119에 자동 신고되었습니다',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 24),
          // 기록 삭제 — 확인한 기록만
          ActionButton(
            label: _event.isAcknowledged ? '기록 삭제' : '확인한 기록만 삭제할 수 있습니다',
            icon: Icons.delete_outline,
            kind: ActionKind.destructive,
            onPressed: (_busy || !_event.isAcknowledged) ? null : _delete,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSub)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: valueColor ?? AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: 통과 확인**

Run: `flutter analyze && flutter test test/fall_list_test.dart test/fall_detail_test.dart`
Expected: analyze 깨끗, PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/fall_list.dart app/lib/screens/fall_detail.dart && git commit -m "feat: 알림 목록·상세를 카드 목록과 상태 히어로 + 공용 동작 버튼으로"
```

---

### Task 8: 사고 발생 창

**Files:**
- Modify: `app/lib/screens/fall_alert_dialog.dart` (전체 교체)
- Test: 기존 `app/test/fall_alert_dialog_test.dart`, `app/test/main_shell_alert_test.dart`

**Interfaces:**
- Consumes: `HeroCard`/`HeroTone`, `ActionButton`/`ActionKind`, `fmtShort` (Task 3); `dial`·`emergencyPhone`
- Produces: 없음(`FallAlertDialog({api, event})` 유지, `PopScope(canPop: false)` 유지)

- [ ] **Step 1: 전체 교체**

```dart
// 낙상 발생 알림 창 — 방·시각을 보여주고 확인 버튼으로만 닫힌다.
// 상세 화면과 같은 전화·119 버튼을 갖는다. 전화를 걸어도 창은 유지된다.

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../dial.dart';
import '../models.dart';
import '../widgets.dart';

class FallAlertDialog extends StatefulWidget {
  const FallAlertDialog({super.key, required this.api, required this.event});

  final Api api;
  final FallEvent event;

  @override
  State<FallAlertDialog> createState() => _FallAlertDialogState();
}

class _FallAlertDialogState extends State<FallAlertDialog> {
  // null = 조회 중. 실패하면 '' — 전화 버튼 비활성 + 안내문 (상세 화면과 같다)
  String? _elderPhone;

  @override
  void initState() {
    super.initState();
    widget.api.getProfile().then((p) {
      if (mounted) setState(() => _elderPhone = p.elderPhone);
    }).catchError((_) {
      if (mounted) setState(() => _elderPhone = '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final phoneRegistered = _elderPhone != null && _elderPhone!.isNotEmpty;
    return PopScope(
      // 뒤로가기·스와이프로 닫히지 않는다. 부르는 쪽의 barrierDismissible: false와
      // 합쳐져 확인 버튼이 유일한 출구가 된다. 전화·119 버튼은 창을 닫지 않는다.
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroCard(
                tone: HeroTone.alert,
                padding: const EdgeInsets.all(18),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('낙상 감지', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('사고 발생', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    SizedBox(height: 4),
                    Text('지금 바로 확인이 필요해요', style: TextStyle(fontSize: 13, color: Color(0xE6FFFFFF))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    _row('방 이름', event.roomName),
                    const Divider(color: AppColors.border),
                    _row('방 번호', '${event.roomNumber}번'),
                    const Divider(color: AppColors.border),
                    _row('발생 시각', fmtShort(event.occurredAt)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 돌봄 대상자에게 전화 — 미등록이면 비활성 + 안내
              ActionButton(
                label: '돌봄 대상자에게 전화',
                icon: Icons.phone,
                kind: ActionKind.outlined,
                onPressed: phoneRegistered ? () => dial(context, _elderPhone!) : null,
              ),
              if (!phoneRegistered) ...[
                const SizedBox(height: 8),
                const Text(
                  '프로필에서 전화번호를 등록하면 켜집니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.textSub),
                ),
              ],
              const SizedBox(height: 10),
              // 119 긴급 신고 — 이미 자동 신고된 이벤트면 잠근다
              ActionButton(
                label: '119 긴급 신고',
                icon: Icons.warning_amber,
                kind: ActionKind.emergency,
                onPressed: event.isReported119 ? null : () => dial(context, emergencyPhone),
              ),
              if (event.isReported119) ...[
                const SizedBox(height: 8),
                const Text(
                  '응답이 없어 119에 자동 신고되었습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 10),
              ActionButton(label: '확인', kind: ActionKind.primary, onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.textSub)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 통과 확인**

Run: `flutter analyze && flutter test test/fall_alert_dialog_test.dart test/main_shell_alert_test.dart`
Expected: analyze 깨끗, PASS(`사고 발생`·`확인`·`2번`·방 이름·`7월 28일 04:35` 형식·안내문 두 개 유지).

- [ ] **Step 3: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/lib/screens/fall_alert_dialog.dart && git commit -m "feat: 사고 발생 창을 빨간 히어로 + 정보 상자 + 공용 동작 버튼으로"
```

---

### Task 9: 방 관리

**Files:**
- Modify: `app/lib/screens/room_management.dart` (`build`·`_roomTile`·`_addTile`·`_deleteRoom` 창·`_RoomEditDialog.build` 교체; `_editRoom`·`_snack`·`_RoomDraft`·컨트롤러 수명 주석은 그대로)
- Test: 기존 `app/test/edit_dialog_test.dart`

**Interfaces:**
- Consumes: `AppCard` (Task 3); `AppColors` (Task 2)
- Produces: 없음(`RoomManagementScreen` 시그니처 유지)

- [ ] **Step 1: import에 `import '../widgets.dart';` 추가, `build` 교체**

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('방 관리'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: widget.unreadCount > 0,
              label: Text('${widget.unreadCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: widget.onGoNotifications,
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: widget.onGoSettings),
          const SizedBox(width: 4),
        ],
      ),
      body: widget.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                // 한 줄 말줄임을 걷어냈다 — 아이폰 폭에서 잘리던 문구라, 확대의 일부는 끝까지 보이는 것이다
                const Text(
                  '방을 등록하면, 낙상 알림이 어디에서 일어났는지 표시됩니다.',
                  style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSub),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.0,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final r in widget.rooms) _roomTile(r),
                    _addTile(),
                  ],
                ),
              ],
            ),
    );
  }
```

- [ ] **Step 2: `_roomTile`·`_addTile` 교체**

```dart
  Widget _roomTile(Room r) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
            child: Text(
              '${r.number}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(r.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 3),
          const Text('기기 연결', style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSub)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                iconSize: 20,
                color: AppColors.textMuted,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editRoom(r),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
              IconButton(
                iconSize: 20,
                color: AppColors.textMuted,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteRoom(r),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ponytail: 시안은 점선 테두리 — Flutter 내장 점선이 없어 실선. 꼭 점선이어야 하면 CustomPainter
  Widget _addTile() {
    return InkWell(
      onTap: () => _editRoom(),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 24, color: AppColors.primary),
            SizedBox(height: 8),
            Text('방 추가', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3: `_deleteRoom`의 `AlertDialog`를 테마에 맡기고 삭제 버튼만 destructive 색으로**

```dart
        return AlertDialog(
          title: Text('${room.name} 삭제'),
          content: const Text('이미 기록된 낙상 이력은 지워지지 않습니다. 이 방에 연결된 기기도 해제됩니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerTint,
                foregroundColor: AppColors.dangerDeep,
              ),
              child: const Text('삭제'),
            ),
          ],
        );
```

- [ ] **Step 4: `_RoomEditDialogState.build` 교체 — 힌트 있는 테마 입력칸**

```dart
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.room == null ? '방 추가' : '방 수정'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(hintText: '방 이름'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(hintText: '방 번호'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop<_RoomDraft>(context, (name: _name.text, number: _number.text)),
          child: const Text('저장'),
        ),
      ],
    );
  }
```

- [ ] **Step 5: 통과 확인**

Run: `flutter analyze && flutter test test/edit_dialog_test.dart`
Expected: analyze 깨끗, PASS(`AlertDialog` 타입 · `Icons.edit_outlined` · `방 추가`/`방 수정`/`저장`/`취소` · `TextField` 순서 유지).

- [ ] **Step 6: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/lib/screens/room_management.dart && git commit -m "feat: 방 관리를 흰 카드 격자와 힌트 있는 수정 창으로"
```

---

### Task 10: 프로필·설정

**Files:**
- Modify: `app/lib/screens/profile.dart` (`build`·`_avatar`·`_sectionCard`·`_row`·`_confirmWithdraw` 창·`_FieldEditDialogState.build` 교체; 편집 로직·`LocalStore` 호출은 그대로)
- Modify: `app/lib/screens/settings.dart` (`build`·`_textScaleSeg`·`_sectionCard` 교체; 로드/저장 로직 그대로)
- Test: 기존 `app/test/edit_dialog_test.dart`(프로필 닉네임 창)

**Interfaces:**
- Consumes: `AppCard`, `NoticeBanner` (Task 3); `AppColors` (Task 2); `TextScale.label`
- Produces: 없음

- [ ] **Step 1: `profile.dart` — import에 `import '../widgets.dart';` 추가, `build` 교체**

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: widget.unreadCount > 0,
              label: Text('${widget.unreadCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: widget.onGoNotifications,
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: widget.onGoSettings),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                _avatar(),
                const SizedBox(height: 12),
                Text(
                  _nickname ?? '보호자님',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4),
                ),
                Text(
                  _contactPhone?.isNotEmpty == true ? _contactPhone! : '연락처 미등록',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AppColors.textSub),
                ),
                const SizedBox(height: 24),
                _sectionCard(
                  heading: '내 정보',
                  rows: [
                    _row('닉네임 변경', _nickname ?? '', () => _editNickname()),
                    _row('연락처 변경', _contactPhone?.isNotEmpty == true ? _contactPhone! : '', () => _editContactPhone()),
                    _row('이메일 변경', _email?.isNotEmpty == true ? _email! : '', () => _editEmail()),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  heading: '돌봄 대상자 정보',
                  rows: [
                    _row(
                      '전화번호',
                      _caredPhone == null
                          ? '불러오는 중'
                          : (_caredPhone!.isEmpty ? '미등록' : _caredPhone!),
                      valueColor: (_caredPhone?.isEmpty ?? false) ? AppColors.danger : null,
                      () => _editCaredPhone(),
                    ),
                    _row('주소', _caredAddress ?? '', () => _editCaredAddress()),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  rows: [
                    _row('로그아웃', '', () => _confirmLogout(), trailingIcon: Icons.logout),
                    _row('회원 탈퇴', '', () => _confirmWithdraw(),
                        trailingIcon: Icons.delete_outline, textColor: AppColors.dangerDeep),
                  ],
                ),
              ],
            ),
    );
  }
```

- [ ] **Step 2: `_avatar`·`_sectionCard`·`_row` 교체**

```dart
  Widget _avatar() {
    return Center(
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
              child: const Icon(Icons.person, size: 44, color: AppColors.primary),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  // 링은 페이지 배경을 오려낸 것처럼 보여야 한다
                  border: Border.all(color: AppColors.bg, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 16, color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({String? heading, required List<Widget> rows}) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (heading != null)
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  heading,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textSub),
                ),
              ),
            ),
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value,
    VoidCallback onTap, {
    IconData? trailingIcon,
    Color? textColor,
    Color? valueColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 17, color: textColor ?? AppColors.text)),
            ),
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(value, style: TextStyle(fontSize: 15, color: valueColor ?? AppColors.textSub)),
              ),
            Icon(trailingIcon ?? Icons.chevron_right, size: 20, color: textColor ?? AppColors.textMuted),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3: `_confirmWithdraw`의 창과 `_FieldEditDialogState.build`를 테마에 맡긴다**

`_confirmWithdraw` 안 `AlertDialog`:

```dart
        return AlertDialog(
          title: const Text('회원 탈퇴'),
          content: const Text('계정과 알림 기록이 모두 삭제되며 되돌릴 수 없습니다. 정말 탈퇴하시겠어요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerTint,
                foregroundColor: AppColors.dangerDeep,
              ),
              child: const Text('탈퇴'),
            ),
          ],
        );
```

`_FieldEditDialogState.build`:

```dart
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(widget.subtitle!),
            ),
          TextField(
            controller: _controller,
            keyboardType: widget.keyboardType,
            style: const TextStyle(fontSize: 17),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop<String>(context, _controller.text),
          child: const Text('저장'),
        ),
      ],
    );
  }
```

- [ ] **Step 4: `settings.dart` — import에 `import '../widgets.dart';` 추가, `build`·`_textScaleSeg`·`_sectionCard` 교체**

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('설정'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                _sectionCard(
                  heading: '앱 설정',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('화면 크기', style: TextStyle(fontSize: 17)),
                      trailing: _textScaleSeg(),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _notificationsOn,
                      onChanged: _setNotificationsOn,
                      title: const Text('알림 설정', style: TextStyle(fontSize: 17)),
                    ),
                  ],
                ),
                if (_showNotifWarning) ...[
                  const SizedBox(height: 16),
                  const NoticeBanner(text: '알림을 끄면 낙상 알림이 더이상 가지 않습니다.'),
                ],
                const SizedBox(height: 16),
                _sectionCard(
                  heading: '지원 및 정보',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('공지사항', style: TextStyle(fontSize: 17)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () => _snack('준비 중입니다'),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('문의하기', style: TextStyle(fontSize: 17)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () => _snack('준비 중입니다'),
                    ),
                    const Divider(),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('앱 버전', style: TextStyle(fontSize: 17)),
                      trailing: Text('MVP v1.0', style: TextStyle(fontSize: 15, color: AppColors.textSub)),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // 작게 · 보통 · 크게 — 연회색 알약 안에서 선택 칸만 초록 틴트
  Widget _textScaleSeg() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in TextScale.values)
            InkWell(
              onTap: () => _setTextScale(s),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: _textScale == s
                    ? BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(999))
                    : null,
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _textScale == s ? FontWeight.w700 : FontWeight.w400,
                    color: _textScale == s ? AppColors.primary : AppColors.textSub,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String heading, required List<Widget> children}) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(heading, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textSub)),
          ),
          ...children,
        ],
      ),
    );
  }
```

- [ ] **Step 5: 통과 확인**

Run: `flutter analyze && flutter test test/edit_dialog_test.dart`
Expected: analyze 깨끗, PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/profile.dart app/lib/screens/settings.dart && git commit -m "feat: 프로필·설정을 흰 카드 묶음·초록 세그먼트·경고 배너로"
```

---

### Task 11: 임시 별칭 제거 · 전체 검증

**Files:**
- Modify: `app/lib/app_theme.dart` (Task 2 Step 6의 별칭 블록 삭제)

- [ ] **Step 1: `AppColors` 끝의 `// ponytail: 화면 태스크(4~10)가 끝나면 지운다` 블록(16줄)을 통째로 지운다**

- [ ] **Step 2: 남은 참조가 없는지 확인**

Run: `flutter analyze`
Expected: `No issues found!` — 오류가 나면 그 파일이 아직 옛 이름을 쓴다는 뜻이니 해당 태스크의 코드로 고친다(별칭을 되살리지 않는다).

- [ ] **Step 3: 전체 테스트와 웹 빌드**

Run: `flutter test && flutter build web --release 2>&1 | tail -3 && ls build/web/assets/fonts/ 2>/dev/null || find build/web -name 'Pretendard-*.otf' | head -3`
Expected: 테스트 전부 PASS(기존 13파일 + `widgets_test.dart`), 웹 빌드 성공, 빌드 산출물에 Pretendard OTF 3개.

- [ ] **Step 4: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add app/lib/app_theme.dart && git commit -m "refactor: 옛 팔레트 이름 호환 별칭 제거 — 화면 전부 새 토큰으로 이전 완료"
```

---

### Task 12: 스크린샷 재캡처 · README 갱신

**Files:**
- Modify: `README.md` (보호자 앱 절 두 줄)
- Modify: `docs/screenshots/01-splash.png` … `14-settings.png` (재캡처, 파일 이름 유지)

- [ ] **Step 1: README 보호자 앱 절 수정**

`- **홈** — 미확인·최근 알림, 방 추가 배너` 를

```
- **홈** — 맨 위 상태 카드가 색으로 답한다(안전=초록 · 미확인 낙상=빨강 · 서버 연결 끊김=회색). 그 아래 내 방 · 최근 알림
```

로, `목록·홈 타일에는 상태 배지가 붙는다(`119 신고됨` > `괜찮다고 말함` > `확인함`/`미확인`). 앱은 기기 다크모드와 무관하게 항상 라이트 테마로 그려진다. 화면 캡쳐는 `docs/screenshots/`에 있다.` 를

```
목록·홈 타일에는 상태 칩이 붙는다(`119 신고됨` > `괜찮다고 말함` > `확인함`/`미확인`). 디자인은 연회색 바탕에 흰 카드 · 초록 포인트 · 긴급은 빨간 그라데이션 카드인 "컬러 히어로" 스타일이고(`docs/superpowers/specs/2026-08-29-app-visual-redesign-design.md`), 글꼴은 Pretendard를 번들해 iOS · Android · 웹에서 같게 보인다. 앱은 기기 다크모드와 무관하게 항상 라이트 테마로 그려진다. 화면 캡쳐는 `docs/screenshots/`에 있다.
```

로 바꾼다.

- [ ] **Step 2: 시뮬레이터·백엔드 준비**

`running-fall-guardian` 스킬을 읽고 그 절차대로 백엔드(Spring Boot + PostgreSQL)를 띄우고 방 3개(거실 1 · 침실 2 · 화장실 3)와 낙상 4건(미확인 1 · 확인함 1 · 괜찮다고 말함 1 · 119 신고됨 1)을 만든다. iOS 시뮬레이터:

```bash
xcrun simctl list devices available | grep -i iphone | head -3     # UDID 하나 고른다
xcrun simctl boot <UDID>; open -a Simulator
cd /Users/munhokang/82107/fall-detection/app && flutter run -d <UDID>
```

백엔드를 띄울 수 없으면(PostgreSQL 없음 등) 서버 없이 열리는 화면(01 스플래시 · 02 시작 · 03 로그인 · 04 회원가입 · 14 설정)만 찍고, 못 찍은 파일 이름을 마지막 보고에 적는다.

- [ ] **Step 3: 화면마다 캡처** (앱을 조작해 해당 화면을 띄운 뒤)

```bash
S=/Users/munhokang/82107/fall-detection/docs/screenshots
xcrun simctl io booted screenshot $S/01-splash.png            # 앱 시작 직후 1초 안
xcrun simctl io booted screenshot $S/02-start.png             # 로그아웃 상태 첫 화면
xcrun simctl io booted screenshot $S/03-login.png
xcrun simctl io booted screenshot $S/04-signup.png
xcrun simctl io booted screenshot $S/05-home.png              # 미확인 0건(초록 히어로)
xcrun simctl io booted screenshot $S/06-fall-alert-dialog.png # 새 낙상 POST 직후 뜨는 창
xcrun simctl io booted screenshot $S/07-home-unread.png       # 미확인 1건(빨간 히어로)
xcrun simctl io booted screenshot $S/08-fall-list.png
xcrun simctl io booted screenshot $S/09-fall-detail.png       # 미확인 건
xcrun simctl io booted screenshot $S/10-rooms.png
xcrun simctl io booted screenshot $S/11-room-add-dialog.png
xcrun simctl io booted screenshot $S/12-profile.png
xcrun simctl io booted screenshot $S/13-withdraw-dialog.png
xcrun simctl io booted screenshot $S/14-settings.png
```

- [ ] **Step 4: 눈으로 대조** — 각 PNG를 열어 스펙 §5와 시안(`.superpowers/brainstorm/2106-1787977035/content/*.html`)에 맞는지, '크게' 배율에서 글자가 잘리지 않는지 본다. 어긋나면 해당 화면 태스크로 돌아가 고치고 다시 찍는다.

- [ ] **Step 5: Commit**

```bash
cd /Users/munhokang/82107/fall-detection && git add README.md docs/screenshots && git commit -m "docs: README 보호자 앱 절 갱신, 새 디자인 스크린샷 재캡처"
```
