// 설정 화면 — 방 등록·수정·삭제와 어르신 전화번호 관리

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final Api api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Room> _rooms = [];
  bool _loading = true;
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rooms = await widget.api.listRooms();
      if (!mounted) return;
      setState(() => _rooms = rooms);
      final profile = await widget.api.getProfile();
      if (!mounted) return;
      _phone.text = profile.elderPhone;
    } catch (e) {
      _snack(e);
    }
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _snack(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  // room이 null이면 추가, 아니면 수정 다이얼로그다.
  Future<void> _editRoom([Room? room]) async {
    final name = TextEditingController(text: room?.name ?? '');
    final number = TextEditingController(text: room?.number.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(room == null ? '방 추가' : '방 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '이름 (예: 안방)'),
              autofocus: true,
            ),
            TextField(
              controller: number,
              decoration: const InputDecoration(labelText: '번호 (예: 1)'),
              keyboardType: TextInputType.number,
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
      _snack(Exception('이름과 숫자 번호를 모두 입력하세요.'));
      return;
    }
    try {
      if (room == null) {
        await widget.api.createRoom(nameText, n);
      } else {
        await widget.api.renameRoom(room.id, nameText, n);
      }
      await _load();
    } catch (e) {
      _snack(e);
    }
  }

  Future<void> _deleteRoom(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${room.label} 삭제'),
        content: const Text('이미 기록된 낙상 이력은 지워지지 않습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteRoom(room.id);
      await _load();
    } catch (e) {
      _snack(e);
    }
  }

  Future<void> _savePhone() async {
    try {
      await widget.api.updateProfile(_phone.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다.')));
    } catch (e) {
      _snack(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('보호자 페이지')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('방 관리', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('감지 페이지가 이 목록에서 방을 고른다.', style: TextStyle(color: Colors.grey)),
                if (_rooms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('등록된 방이 없습니다. 방을 추가하세요.'),
                  ),
                for (final room in _rooms)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(room.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editRoom(room)),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRoom(room)),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _editRoom(),
                  icon: const Icon(Icons.add),
                  label: const Text('방 추가'),
                ),
                const SizedBox(height: 32),
                Text('어르신 전화번호', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('상세 화면의 "어르신께 전화" 버튼이 이 번호로 건다.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '01012345678', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _savePhone, child: const Text('저장')),
              ],
            ),
    );
  }
}
