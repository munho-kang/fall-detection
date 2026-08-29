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
                      child: Text(
                        r.label,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSub),
                      ),
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
