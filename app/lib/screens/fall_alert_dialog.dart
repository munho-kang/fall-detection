// 낙상 발생 알림 창 — 방·시각을 보여주고 확인 버튼으로만 닫힌다

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

class FallAlertDialog extends StatelessWidget {
  const FallAlertDialog({super.key, required this.event});

  final FallEvent event;

  // 홈·알림 목록과 같은 형식이다
  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // 뒤로가기·스와이프로 닫히지 않는다. 부르는 쪽의 barrierDismissible: false와
      // 합쳐져 확인 버튼이 유일한 출구가 된다.
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, size: 40, color: scheme.error),
        title: const Text('사고 발생', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(context, '방 이름', event.roomName),
            _row(context, '방 번호', '${event.roomNumber}번'),
            _row(context, '발생 시각', _fmt(event.occurredAt)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              child: const Text('확인'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
