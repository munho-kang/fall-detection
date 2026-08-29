// 방 관리 탭 — 2열 흰 카드 격자, 방 추가/수정/삭제

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../models.dart';
import '../widgets.dart';

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
      appBar: AppBar(
        title: const Text('방 관리'),
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                // 한 줄 말줄임을 걷어냈다 — 아이폰 폭에서 잘리던 문구라, 확대의 일부는 끝까지 보이는 것이다.
                // 줄바꿈을 직접 넣는다: 자동 줄바꿈은 아이폰 폭에서 "다." 한 글자만 다음 줄로 떨군다
                const Text(
                  '방을 등록하면,\n낙상 알림이 어디에서 일어났는지 표시됩니다.',
                  style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSub),
                ),
                const SizedBox(height: 16),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
            child: Text(
              '${r.number}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(r.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 3),
          const Text('기기 연결', style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSub)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                iconSize: 20,
                color: AppColors.textMuted,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editRoom(r),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
              IconButton(
                iconSize: 20,
                color: AppColors.textMuted,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteRoom(r),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ponytail: 시안은 점선 테두리 — Flutter 내장 점선이 없어 실선. 꼭 점선이어야 하면 CustomPainter
  Widget _addTile() {
    return InkWell(
      onTap: () => _editRoom(),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 24, color: AppColors.primary),
            SizedBox(height: 8),
            Text('방 추가', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  Future<void> _editRoom([Room? room]) async {
    // 입력값은 창이 pop할 때 결과로 받는다 — 컨트롤러는 창이 소유한다(_RoomEditDialog 주석).
    final entered = await showDialog<_RoomDraft>(
      context: context,
      builder: (_) => _RoomEditDialog(room: room),
    );
    if (entered == null) return; // 취소
    final nameText = entered.name.trim();
    final n = int.tryParse(entered.number.trim());
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
      builder: (context) {
        return AlertDialog(
          title: Text('${room.name} 삭제'),
          content: const Text('이미 기록된 낙상 이력은 지워지지 않습니다. 이 방에 연결된 기기도 해제됩니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerTint,
                foregroundColor: AppColors.dangerDeep,
              ),
              child: const Text('삭제'),
            ),
          ],
        );
      },
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

// 방 추가·수정 창이 입력한 값 — 다듬기·숫자 변환은 받는 쪽이 한다
typedef _RoomDraft = ({String name, String number});

// 컨트롤러를 창이 소유해야 하는 이유: showDialog가 돌려주는 future는 pop 시점에 곧바로
// 완료되지만 라우트는 퇴장 애니메이션이 끝날 때까지 살아 있다. 호출부에서 future를
// 받자마자 dispose하면 그 사이 리빌드되는 TextField가 죽은 컨트롤러를 구독해
// "A TextEditingController was used after being disposed"로 터진다.
// State.dispose는 라우트가 언마운트될 때(=TextField가 사라진 뒤) 불려 안전하다.
class _RoomEditDialog extends StatefulWidget {
  const _RoomEditDialog({this.room});

  final Room? room;

  @override
  State<_RoomEditDialog> createState() => _RoomEditDialogState();
}

class _RoomEditDialogState extends State<_RoomEditDialog> {
  late final _name = TextEditingController(text: widget.room?.name ?? '');
  late final _number = TextEditingController(text: widget.room?.number.toString() ?? '');

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.room == null ? '방 추가' : '방 수정'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(hintText: '방 이름'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(hintText: '방 번호'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop<_RoomDraft>(context, (name: _name.text, number: _number.text)),
          child: const Text('저장'),
        ),
      ],
    );
  }
}
