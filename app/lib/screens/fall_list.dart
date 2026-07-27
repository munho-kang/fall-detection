// 알림 확인 창 — 전체 알림 목록 · 알림을 누르면 낙상 이벤트 상세로

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';
import '../models.dart';
import 'fall_detail.dart';

class FallListScreen extends StatefulWidget {
  const FallListScreen({
    super.key,
    required this.api,
    required this.events,
    required this.loading,
    required this.connectionError,
    required this.onLogout,
    required this.onRefresh,
  });

  final Api api;
  final List<FallEvent> events;
  final bool loading;
  final String? connectionError;
  final VoidCallback onLogout;
  final Future<void> Function() onRefresh;

  @override
  State<FallListScreen> createState() => _FallListScreenState();
}

class _FallListScreenState extends State<FallListScreen> {
  late List<FallEvent> _events;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _events = widget.events;
    _error = widget.connectionError;
    // 이 화면은 MainShell 위에 push된 라우트라 폴러의 setState가 닿지 않는다.
    // 열려 있는 동안 괜찮음 응답·119 자동 신고가 반영되도록 상세 화면과 같은 5초 재조회를 쓴다.
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refetch());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refetch() async {
    try {
      final events = await widget.api.listFalls();
      if (!mounted) return;
      setState(() {
        _events = events;
        _error = null;
      });
    } on UnauthorizedException {
      // MainShell의 폴러가 같은 401을 받아 로그아웃을 처리한다
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '서버와 연결이 끊겼습니다.');
    }
  }

  @override
  void didUpdateWidget(covariant FallListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events) {
      _events = widget.events;
    }
    if (oldWidget.connectionError != widget.connectionError) {
      _error = widget.connectionError;
    }
  }

  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _refresh() async {
    await widget.onRefresh(); // MainShell의 배지·홈 목록 갱신
    await _refetch(); // 이 화면 자체는 스냅샷이라 직접 다시 받는다
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('알림', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: AppColors.onErrorContainer)),
              ),
              const SizedBox(height: 16),
            ],
            if (_events.isEmpty)
              SizedBox(
                height: 400,
                child: Center(
                  child: Text(
                    '아직 감지된 낙상이 없습니다.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              // ListTile은 가장 가까운 Material에 배경·잉크를 그린다 — 색 있는 Container로 감싸면
              // 디버그 검증이 예외를 던지므로 방 추가 카드처럼 Material을 쓴다.
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (int i = 0; i < _events.length; i++) ...[
                      _alertTile(_events[i]),
                      if (i < _events.length - 1)
                        const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.outlineVariant),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _alertTile(FallEvent e) {
    final acknowledged = e.isAcknowledged;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(
        acknowledged ? Icons.check_circle : Icons.warning_amber,
        color: acknowledged ? AppColors.onSurfaceVariant : AppColors.error,
      ),
      title: Text(
        e.roomLabel,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: acknowledged ? AppColors.onSurfaceVariant : AppColors.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(_fmt(e.occurredAt), style: const TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant)),
      ),
      // 우선순위: 119 신고됨 > 괜찮다고 말함 > 확인함/미확인 — 안전 쪽이 이긴다
      trailing: e.isReported119
          ? const Text(
              '119 신고됨',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.error),
            )
          : e.isVoiceOk
              ? const Text(
                  '괜찮다고 말함',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary),
                )
              : Text(
                  acknowledged ? '확인함' : '미확인',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: acknowledged ? AppColors.onSurfaceVariant : AppColors.error,
                  ),
                ),
      onTap: () async {
        await Navigator.of(context).push<FallEvent>(
          MaterialPageRoute(builder: (_) => FallDetailScreen(api: widget.api, event: e)),
        );
        // 돌아오면 MainShell 폴러가 곧 반영하지만, 즉시 새로고침 트리거
        await _refresh();
      },
    );
  }
}
