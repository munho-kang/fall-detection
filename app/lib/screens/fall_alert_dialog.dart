// 낙상 발생 알림 창 — 방·시각을 보여주고 확인 버튼으로만 닫힌다.
// 상세 화면과 같은 전화·119 버튼을 갖는다. 전화를 걸어도 창은 유지된다.

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../dial.dart';
import '../models.dart';

class FallAlertDialog extends StatefulWidget {
  const FallAlertDialog({super.key, required this.api, required this.event});

  final Api api;
  final FallEvent event;

  @override
  State<FallAlertDialog> createState() => _FallAlertDialogState();
}

class _FallAlertDialogState extends State<FallAlertDialog> {
  // null = 조회 중. 실패하면 '' — 전화 버튼 비활성 + 안내문 (상세 화면과 같다)
  String? _elderPhone;

  @override
  void initState() {
    super.initState();
    widget.api.getProfile().then((p) {
      if (mounted) setState(() => _elderPhone = p.elderPhone);
    }).catchError((_) {
      if (mounted) setState(() => _elderPhone = '');
    });
  }

  // 홈·알림 목록과 같은 형식이다
  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final event = widget.event;
    final phoneRegistered = _elderPhone != null && _elderPhone!.isNotEmpty;
    // 상세 화면 _actionButton과 같은 비활성 색 — onSurface에 Material 알파(배경 12% · 전경 38%)
    final disabledBg = scheme.onSurface.withValues(alpha: 0.12);
    final disabledFg = scheme.onSurface.withValues(alpha: 0.38);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return PopScope(
      // 뒤로가기·스와이프로 닫히지 않는다. 부르는 쪽의 barrierDismissible: false와
      // 합쳐져 확인 버튼이 유일한 출구가 된다. 전화·119 버튼은 창을 닫지 않는다.
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
          // AlertDialog의 가로 OverflowBar 대신 Column으로 세로 스택 — 간격을 직접
          // 제어하고 안내문을 버튼 바로 아래 붙인다
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 돌봄 대상자에게 전화 — 미등록이면 비활성 + 안내
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: phoneRegistered ? () => dial(context, _elderPhone!) : null,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: scheme.surfaceContainer,
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outline),
                    disabledForegroundColor: disabledFg,
                    shape: shape,
                  ),
                  child: _buttonLabel(Icons.phone, '돌봄 대상자에게 전화'),
                ),
              ),
              if (!phoneRegistered) ...[
                const SizedBox(height: 8),
                Text(
                  '프로필에서 전화번호를 등록하면 켜집니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              // 119 긴급 신고 — 이미 자동 신고된 이벤트면 잠근다
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: event.isReported119 ? null : () => dial(context, emergencyPhone),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: disabledBg,
                    disabledForegroundColor: disabledFg,
                    shape: shape,
                  ),
                  child: _buttonLabel(Icons.warning_amber, '119 긴급 신고'),
                ),
              ),
              if (event.isReported119) ...[
                const SizedBox(height: 8),
                Text(
                  '응답이 없어 119에 자동 신고되었습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: shape,
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 상세 화면 _actionButton의 안쪽 Row와 같은 구성이다
  Widget _buttonLabel(IconData icon, String label) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      );

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
