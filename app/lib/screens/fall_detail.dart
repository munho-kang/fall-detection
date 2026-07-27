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

  @override
  void initState() {
    super.initState();
    widget.api.getProfile().then((p) {
      if (mounted) setState(() => _elderPhone = p.elderPhone);
    }).catchError((_) {
      // 못 불러오면 미등록으로 취급한다. 버튼만 비활성화되고 화면은 정상 동작한다.
      if (mounted) setState(() => _elderPhone = '');
    });
  }

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

  Future<void> _delete() async {
    // 완전 삭제라 되돌릴 수 없다. 웹의 confirm()과 같은 무게로 확인을 받는다.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록을 삭제할까요?'),
        content: Text('${_event.roomLabel} · ${_fmt(_event.occurredAt)}\n\n삭제하면 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;   // 다이얼로그가 열려 있는 사이 화면이 사라졌으면 setState가 터진다.

    setState(() => _busy = true);
    try {
      await widget.api.deleteFall(_event.id);
      if (!mounted) return;
      // 결과 없이 pop 한다. 목록이 null 경로에서 서버 상태로 다시 그린다.
      Navigator.of(context).pop();
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

  // null = 아직 불러오는 중, '' = 미등록. 설정 화면에서 등록한 번호를 쓴다.
  String? _elderPhone;

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
        // 삭제와 iOS 스와이프 백은 null이 되고, 목록이 그때 서버에서 다시 받아 그린다.
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
            // 로딩 중(null)이거나 미등록('')이면 누를 수 없다.
            onPressed: _elderPhone == null || _elderPhone!.isEmpty ? null : () => _dial(_elderPhone!),
            icon: const Icon(Icons.phone),
            label: Text(_elderPhone == '' ? '어르신께 전화 — 설정에서 번호 등록' : '어르신께 전화'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _dial(_emergencyPhone),
            icon: const Icon(Icons.local_hospital),
            label: const Text('119 신고 (시연용 더미 번호)'),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            // 서버가 400으로 막는 규칙(확인한 기록만 삭제)을 화면이 미리 설명한다.
            onPressed: _busy || !_event.isAcknowledged ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(_event.isAcknowledged ? '기록 삭제' : '확인한 뒤 삭제할 수 있습니다'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
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
