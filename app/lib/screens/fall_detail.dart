// 낙상 이벤트 상세 화면

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

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

  Future<void> _acknowledge() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.api.acknowledge(_event.id);
      if (!mounted) return;
      setState(() {
        _event = updated;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  String _fmt(DateTime t) =>
      '${t.year}년 ${t.month}월 ${t.day}일 '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_event.roomLabel),
        // 목록이 확인 상태를 즉시 반영할 수 있도록 갱신된 이벤트를 돌려준다.
        // iOS 스와이프 백으로 나가면 null이 되지만, 5초 폴링이 곧 목록을 새로 고친다.
        leading: BackButton(onPressed: () => Navigator.of(context).pop(_event)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('발생 시각', _fmt(_event.occurredAt)),
          _row('감지 신뢰도', '${(_event.confidence * 100).toStringAsFixed(0)}%'),
          _row('상태', _event.isAcknowledged ? '확인함 (${_fmt(_event.acknowledgedAt!)})' : '미확인'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy || _event.isAcknowledged ? null : _acknowledge,
            icon: const Icon(Icons.check),
            label: Text(_event.isAcknowledged ? '확인함' : '확인함으로 표시'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
          ],
        ),
      );
}
