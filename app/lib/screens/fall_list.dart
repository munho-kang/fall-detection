// 낙상 이벤트 목록 화면

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../poller.dart';
import 'fall_detail.dart';
import 'login.dart';
import 'settings.dart';

class FallListScreen extends StatefulWidget {
  const FallListScreen({super.key, required this.api});

  final Api api;

  @override
  State<FallListScreen> createState() => _FallListScreenState();
}

class _FallListScreenState extends State<FallListScreen> {
  List<FallEvent> _events = [];
  bool _loading = true;
  String? _error;
  late final FallPoller _poller;

  @override
  void initState() {
    super.initState();
    _poller = FallPoller(
      api: widget.api,
      onEvents: (all, fresh, newlyOk) {
        for (final e in fresh) {
          Notifications.show(e);
        }
        // 괜찮음이 새로 도착한 이벤트 — 같은 id로 다시 띄워 트레이의 알림 문구를 교체한다
        for (final e in newlyOk) {
          Notifications.show(e);
        }
        if (!mounted) return;
        setState(() {
          _events = all;
          _loading = false;
          _error = null;
        });
      },
      onConnectionLost: () {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '연결 끊김 — 서버에 닿지 않습니다.';
        });
      },
      onRecovered: () {
        if (!mounted) return;
        setState(() => _error = null);
      },
      onUnauthorized: _logout,
    );
    _poller.start();
  }

  @override
  void dispose() {
    _poller.stop();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final events = await widget.api.listFalls();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
        _error = null;
      });
    } on UnauthorizedException {
      await _logout();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _logout() async {
    await widget.api.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
    );
  }

  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('낙상 알림'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(api: widget.api)),
            ),
            child: const Text('보호자 페이지'),
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: Column(
                children: [
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.errorContainer,
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  Expanded(
                    child: _events.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('아직 감지된 낙상이 없습니다.')),
                            ],
                          )
                        : ListView.separated(
                            itemCount: _events.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final e = _events[i];
                              return ListTile(
                                leading: Icon(
                                  e.isAcknowledged ? Icons.check_circle : Icons.warning_amber,
                                  color: e.isAcknowledged
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.error,
                                ),
                                title: Text(e.roomLabel),
                                subtitle: Text(_fmt(e.occurredAt)),
                                trailing: e.isReported119
                                    ? Text(
                                        '119 신고됨',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : Text(e.isAcknowledged ? '확인함' : '미확인'),
                                onTap: () async {
                                  final updated = await Navigator.of(context).push<FallEvent>(
                                    MaterialPageRoute(
                                      builder: (_) => FallDetailScreen(api: widget.api, event: e),
                                    ),
                                  );
                                  if (updated != null) {
                                    final idx = _events.indexWhere((x) => x.id == updated.id);
                                    if (idx != -1) setState(() => _events[idx] = updated);
                                  } else {
                                    // 삭제했거나 스와이프 백으로 나왔다 — 서버 상태로 다시 그린다.
                                    await _refresh();
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
