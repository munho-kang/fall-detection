// 알림 확인 창 — 전체 알림 목록 · 알림을 누르면 낙상 이벤트 상세로

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../models.dart';
import '../widgets.dart';
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

  Future<void> _refresh() async {
    await widget.onRefresh(); // MainShell의 배지·홈 목록 갱신
    await _refetch(); // 이 화면 자체는 스냅샷이라 직접 다시 받는다
  }

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
}
