// 낙상 이벤트 상세 화면

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // 연락처 관리 화면은 범위 밖이므로 상수로 둔다.
  static const _elderPhone = '01012345678';

  // 시연 중 실수로 119에 실제 신고가 나가면 안 되므로 더미 번호다.
  // 실제 제품에서는 '119'로 바꾼다.
  static const _emergencyPhone = '01000000119';

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    // 다이얼러에 번호를 띄우는 데까지만 한다. 실제 발신은 사용자가 누른다.
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화 앱을 열 수 없습니다.')),
      );
    }
  }

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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _dial(_elderPhone),
            icon: const Icon(Icons.phone),
            label: const Text('어르신께 전화'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _dial(_emergencyPhone),
            icon: const Icon(Icons.local_hospital),
            label: const Text('119 신고 (시연용 더미 번호)'),
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
