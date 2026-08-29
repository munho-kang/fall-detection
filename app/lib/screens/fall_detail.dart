// 낙상 이벤트 상세 화면 — 알림 확인 창에서 진입 · 뒤로 가기로 갱신된 이벤트를 목록에 돌려줌

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../dial.dart';
import '../models.dart';
import '../widgets.dart';

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
  String? _elderPhone;

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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerDeep),
            child: const Text('삭제'),
          ),
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

  void _snack(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}
