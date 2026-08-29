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
