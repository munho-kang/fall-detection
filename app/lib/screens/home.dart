// 홈 화면 (메인) — 상단 바(알림 · 설정) + 방 추가 배너 + 미확인/최근 알림

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';
import '../models.dart';
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

  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final unread = events.where((e) => !e.isAcknowledged).toList();
    final recent = events.where((e) => e.isAcknowledged).toList();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('홈 화면', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
        padding: const EdgeInsets.all(16),
        children: [
          // 방 추가 배너 — 방이 있어도 항상 노출(누르면 방 관리 탭으로)
          _addRoomCard(context),
          const SizedBox(height: 20),
          if (connectionError != null) ...[
            _connectionBanner(context),
            const SizedBox(height: 16),
          ],
          Text('확인하지 않은 알림', style: _titleStyle(context)),
          const SizedBox(height: 8),
          if (loadingEvents)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (unread.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '아직 감지된 낙상이 없습니다.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            _alertCard(context, unread, onlyFirst: true, dimTitle: false),
          const SizedBox(height: 20),
          if (recent.isNotEmpty) ...[
            Text('최근 확인한 알림', style: _titleStyle(context)),
            const SizedBox(height: 8),
            _alertCard(context, recent, onlyFirst: false, dimTitle: true),
          ],
        ],
      ),
    );
  }

  TextStyle _titleStyle(BuildContext context) => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      );

  Widget _addRoomCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onChangeTab(1),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.grid_view, size: 32, color: scheme.onPrimaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '방 추가',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '방을 등록해 두세요.',
                      style: TextStyle(fontSize: 15, color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connectionError!,
              style: TextStyle(fontSize: 15, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertCard(BuildContext context, List<FallEvent> list, {required bool onlyFirst, required bool dimTitle}) {
    final items = onlyFirst ? list.take(1).toList() : list;
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _alertTile(context, items[i], dimTitle: dimTitle),
            if (i < items.length - 1)
              Divider(height: 1, indent: 16, endIndent: 16, color: outlineVariant),
          ],
        ],
      ),
    );
  }

  Widget _alertTile(BuildContext context, FallEvent e, {required bool dimTitle}) {
    final acknowledged = e.isAcknowledged;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(
        acknowledged ? Icons.check_circle : Icons.warning_amber,
        color: acknowledged ? scheme.onSurfaceVariant : AppColors.error,
      ),
      title: Text(
        e.roomLabel,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: dimTitle ? scheme.onSurfaceVariant : scheme.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(_fmt(e.occurredAt), style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
      ),
      // 우선순위: 119 신고됨 > 괜찮다고 말함 > 확인함/미확인 — 알림 확인 창과 같다
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
                    color: acknowledged ? scheme.onSurfaceVariant : AppColors.error,
                  ),
                ),
      onTap: () async {
        await Navigator.of(context).push<FallEvent>(
          MaterialPageRoute(builder: (_) => FallDetailScreen(api: api, event: e)),
        );
        // 홈에서는 별도 갱신 로직 없음 — MainShell의 폴러가 다음 틱에 반영
      },
    );
  }
}
