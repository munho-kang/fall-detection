// 메인 셸 — 하단 네비게이션(홈 · 방 관리 · 프로필)과 폴러 보유. 토글은 설정 화면에서 바꾼다

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../poller.dart';
import 'fall_list.dart';
import 'home.dart';
import 'login.dart';
import 'profile.dart';
import 'room_management.dart';
import 'settings.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.api, this.onSettingsResume});

  final Api api;
  // 설정 화면에서 돌아오면 불린다 — main.dart에서 prefs를 다시 읽어 다크모드/배율 적용
  final VoidCallback? onSettingsResume;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  List<FallEvent> _events = [];
  List<Room> _rooms = [];
  bool _loadingEvents = true;
  bool _loadingRooms = true;
  String? _connectionError;
  late final FallPoller _poller;

  @override
  void initState() {
    super.initState();
    _poller = FallPoller(
      api: widget.api,
      onEvents: (all, fresh, newlyOk) async {
        for (final e in fresh) {
          await Notifications.show(e);
        }
        for (final e in newlyOk) {
          await Notifications.show(e);
        }
        if (!mounted) return;
        setState(() {
          _events = all;
          _loadingEvents = false;
          _connectionError = null;
        });
      },
      onConnectionLost: () {
        if (!mounted) return;
        setState(() {
          _loadingEvents = false;
          _connectionError = '서버와 연결이 끊겼습니다.';
        });
      },
      onRecovered: () {
        if (!mounted) return;
        setState(() => _connectionError = null);
      },
      onUnauthorized: _logout,
    );
    _poller.start();
    _loadRooms();
  }

  @override
  void dispose() {
    _poller.stop();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await widget.api.listRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loadingRooms = false;
      });
    } on UnauthorizedException {
      await _logout();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRooms = false);
    }
  }

  Future<void> _logout() async {
    await widget.api.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
      (route) => false,
    );
  }

  // 폴러 목록을 다시 당겨온다 — 방 관리·상세에서 변동이 있을 때
  Future<void> refreshFalls() async {
    try {
      final events = await widget.api.listFalls();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loadingEvents = false;
        _connectionError = null;
      });
    } on UnauthorizedException {
      await _logout();
    } catch (_) {}
  }

  // 방 목록을 다시 당겨온다 — 방 관리에서 변동 시
  Future<void> reloadRooms() => _loadRooms();

  void _goNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FallListScreen(
          api: widget.api,
          events: _events,
          loading: _loadingEvents,
          connectionError: _connectionError,
          onLogout: _logout,
          onRefresh: refreshFalls,
        ),
      ),
    );
  }

  void _goSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    // 돌아오면 main.dart에 prefs를 다시 읽으라고 알림
    widget.onSettingsResume?.call();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _events.where((e) => !e.isAcknowledged).length;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            events: _events,
            rooms: _rooms,
            loadingEvents: _loadingEvents,
            loadingRooms: _loadingRooms,
            connectionError: _connectionError,
            unreadCount: unreadCount,
            onGoNotifications: _goNotifications,
            onGoSettings: _goSettings,
            onChangeTab: (i) => setState(() => _tab = i),
            api: widget.api,
            onLogout: _logout,
          ),
          RoomManagementScreen(
            api: widget.api,
            rooms: _rooms,
            loading: _loadingRooms,
            reload: reloadRooms,
            unreadCount: unreadCount,
            onGoNotifications: _goNotifications,
            onGoSettings: _goSettings,
          ),
          ProfileScreen(
            api: widget.api,
            unreadCount: unreadCount,
            onGoNotifications: _goNotifications,
            onGoSettings: _goSettings,
            onLogout: _logout,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        height: 80,
        indicatorColor: AppColors.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
    );
  }
}
