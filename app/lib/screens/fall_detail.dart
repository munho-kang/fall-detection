// 낙상 이벤트 상세 화면 — 알림 확인 창에서 진입 · 뒤로 가기로 갱신된 이벤트를 목록에 돌려줌

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart' show AppColors, dangerColors;
import '../dial.dart';
import '../models.dart';

class FallDetailScreen extends StatefulWidget {
  const FallDetailScreen({super.key, required this.api, required this.event});

  final Api api;
  final FallEvent event;

  @override
  State<FallDetailScreen> createState() => _FallDetailScreenState();
}

class _FallDetailScreenState extends State<FallDetailScreen> {
  late FallEvent _event = widget.event;
  bool _busy = false;
  Timer? _refreshTimer;
  int _actionEpoch = 0;

  @override
  void initState() {
    super.initState();
    widget.api.getProfile().then((p) {
      if (mounted) setState(() => _elderPhone = p.elderPhone);
    }).catchError((_) {
      if (mounted) setState(() => _elderPhone = '');
    });
    // 119 자동 신고가 도착하면 실시간으로 잠기도록 5초마다 다시 읽는다
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refetch());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refetch() async {
    final epoch = _actionEpoch;
    try {
      final events = await widget.api.listFalls();
      final idx = events.indexWhere((e) => e.id == _event.id);
      if (idx != -1 && mounted && !_busy && epoch == _actionEpoch) {
        setState(() => _event = events[idx]);
      }
    } on UnauthorizedException {
      // 목록 화면의 폴러(이제 MainShell)가 같은 401을 받아 로그아웃 처리
    } catch (_) {
      // 일시 오류 — 다음 주기가 다시 시도한다.
    }
  }

  Future<void> _acknowledge() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.api.acknowledge(_event.id);
      if (!mounted) return;
      setState(() {
        _event = updated;
        _actionEpoch += 1;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록을 삭제할까요?'),
        content: Text('${_event.roomName} · ${_fmt(_event.occurredAt)}\n\n삭제하면 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await widget.api.deleteFall(_event.id);
      if (!mounted) return;
      _actionEpoch += 1;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e);
    }
  }

  String _fmt(DateTime t) =>
      '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String? _elderPhone;

  @override
  Widget build(BuildContext context) {
    final phoneRegistered = _elderPhone != null && _elderPhone!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop(_event)),
        title: const Text('알림', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 정보 카드
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
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
                  _event.isAcknowledged
                      ? '확인함 (${_fmt(_event.acknowledgedAt!)})'
                      : '미확인',
                  valueColor: _event.isAcknowledged ? Theme.of(context).colorScheme.onSurfaceVariant : AppColors.error,
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
          const SizedBox(height: 28),
          // 알림 확인 버튼 — 확인 완료 시 비활성
          _actionButton(
            label: _event.isAcknowledged ? '알림 확인' : '알림 확인',
            icon: Icons.check,
            enabled: !_busy && !_event.isAcknowledged,
            filled: true,
            onPressed: _acknowledge,
          ),
          const SizedBox(height: 12),
          // 돌봄 대상자에게 전화 — 미등록이면 비활성 + 안내
          _actionButton(
            label: '돌봄 대상자에게 전화',
            icon: Icons.phone,
            enabled: phoneRegistered,
            filled: false,
            outlinedWithSurface: true,
            onPressed: phoneRegistered ? () => dial(context, _elderPhone!) : null,
          ),
          if (!phoneRegistered) ...[
            const SizedBox(height: 8),
            Text(
              '프로필에서 전화번호를 등록하면 켜집니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          // 119 긴급 신고
          _actionButton(
            label: '119 긴급 신고',
            icon: Icons.warning_amber,
            enabled: !_event.isReported119,
            filled: false,
            emergency: true,
            onPressed: _event.isReported119 ? null : () => dial(context, emergencyPhone),
          ),
          if (_event.isReported119)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '응답이 없어 119에 자동 신고되었습니다',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 28),
          // 기록 삭제 — 확인한 기록만
          _actionButton(
            label: _event.isAcknowledged ? '기록 삭제' : '확인한 기록만 삭제할 수 있습니다',
            icon: Icons.delete_outline,
            enabled: _busy ? false : _event.isAcknowledged,
            filled: false,
            danger: true,
            onPressed: _event.isAcknowledged ? _delete : null,
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
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: valueColor ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required bool filled,
    bool outlinedWithSurface = false,
    bool emergency = false,
    bool danger = false,
    VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 원래 상수 Color(0x1F191C1B) · Color(0x61191C1B)는 라이트 onSurface에
    // Material 비활성 알파(배경 12% · 전경 38%)를 씌운 값이다. 의미를 그대로 두고 밝기만 따라가게 한다.
    final disabledBg = scheme.onSurface.withValues(alpha: 0.12);
    final disabledFg = scheme.onSurface.withValues(alpha: 0.38);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final inner = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ],
    );

    if (filled) {
      return SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: disabledBg,
            disabledForegroundColor: disabledFg,
            shape: shape,
          ),
          child: inner,
        ),
      );
    }
    if (emergency) {
      return SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: disabledBg,
            disabledForegroundColor: disabledFg,
            shape: shape,
          ),
          child: inner,
        ),
      );
    }
    if (danger) {
      final tone = dangerColors(Theme.of(context).brightness);
      return SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: tone.bg,
            foregroundColor: tone.fg,
            disabledBackgroundColor: tone.bg.withValues(alpha: 0.4),
            disabledForegroundColor: tone.fg.withValues(alpha: 0.38),
            shape: shape,
          ),
          child: inner,
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: outlinedWithSurface ? scheme.surfaceContainer : null,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          disabledForegroundColor: disabledFg,
          shape: shape,
        ),
        child: inner,
      ),
    );
  }

  void _snack(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}
