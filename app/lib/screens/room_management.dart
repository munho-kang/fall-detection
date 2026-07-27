// 방 관리 탭 — 2열 네모 격자 카드, 방 추가/수정/삭제

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';
import '../models.dart';

class RoomManagementScreen extends StatefulWidget {
  const RoomManagementScreen({
    super.key,
    required this.api,
    required this.rooms,
    required this.loading,
    required this.reload,
    required this.unreadCount,
    required this.onGoNotifications,
    required this.onGoSettings,
  });

  final Api api;
  final List<Room> rooms;
  final bool loading;
  final Future<void> Function() reload;
  final int unreadCount;
  final VoidCallback onGoNotifications;
  final VoidCallback onGoSettings;

  @override
  State<RoomManagementScreen> createState() => _RoomManagementScreenState();
}

class _RoomManagementScreenState extends State<RoomManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        title: const Text('방 관리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
              padding: const EdgeInsets.all(16),
              children: [
                // 한 줄 말줄임을 걷어냈다 — 아이폰 폭에서 잘리던 문구라, 확대의 일부는 끝까지 보이는 것이다
                const Text(
                  '방을 등록하면, 낙상 알림이 어디에서 일어났는지 표시됩니다.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.onSurfaceVariant, letterSpacing: -0.01),
                ),
                const SizedBox(height: 12),
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

  Widget _roomTile(Room r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${r.number}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            r.name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 3),
          const Text(
            '기기 연결',
            style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.onSurfaceVariant),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                iconSize: 20,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editRoom(r),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                iconSize: 20,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteRoom(r),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addTile() {
    return InkWell(
      onTap: () => _editRoom(),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outline, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 24, color: AppColors.primary),
            SizedBox(height: 8),
            Text(
              '방 추가',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRoom([Room? room]) async {
    final name = TextEditingController(text: room?.name ?? '');
    final number = TextEditingController(text: room?.number.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: Text(
          room == null ? '방 추가' : '방 수정',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 라벨 없는 밑줄형 — 다이얼로그 내부 입력
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                border: UnderlineInputBorder(),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary, width: 2)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: UnderlineInputBorder(),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
        ],
      ),
    );
    final nameText = name.text.trim();
    final n = int.tryParse(number.text.trim());
    name.dispose();
    number.dispose();
    if (saved != true) return;
    if (nameText.isEmpty || n == null) {
      _snack('이름과 숫자 번호를 모두 입력하세요.');
      return;
    }
    try {
      if (room == null) {
        await widget.api.createRoom(nameText, n);
      } else {
        await widget.api.renameRoom(room.id, nameText, n);
      }
      await widget.reload();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteRoom(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: Text(
          '${room.name} 삭제',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          '이미 기록된 낙상 이력은 지워지지 않습니다. 이 방에 연결된 기기도 해제됩니다.',
          style: TextStyle(fontSize: 15, color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerBg,
              foregroundColor: AppColors.dangerFg,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteRoom(room.id);
      await widget.reload();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
