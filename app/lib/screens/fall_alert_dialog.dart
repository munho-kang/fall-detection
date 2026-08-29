// 낙상 발생 알림 창 — 방·시각을 보여주고 확인 버튼으로만 닫힌다.
// 상세 화면과 같은 전화·119 버튼을 갖는다. 전화를 걸어도 창은 유지된다.

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../dial.dart';
import '../models.dart';
import '../widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final phoneRegistered = _elderPhone != null && _elderPhone!.isNotEmpty;
    return PopScope(
      // 뒤로가기·스와이프로 닫히지 않는다. 부르는 쪽의 barrierDismissible: false와
      // 합쳐져 확인 버튼이 유일한 출구가 된다. 전화·119 버튼은 창을 닫지 않는다.
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroCard(
                tone: HeroTone.alert,
                padding: const EdgeInsets.all(18),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('낙상 감지', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('사고 발생', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    SizedBox(height: 4),
                    Text('지금 바로 확인이 필요해요', style: TextStyle(fontSize: 13, color: Color(0xE6FFFFFF))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    _row('방 이름', event.roomName),
                    const Divider(color: AppColors.border),
                    _row('방 번호', '${event.roomNumber}번'),
                    const Divider(color: AppColors.border),
                    _row('발생 시각', fmtShort(event.occurredAt)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 돌봄 대상자에게 전화 — 미등록이면 비활성 + 안내
              ActionButton(
                label: '돌봄 대상자에게 전화',
                icon: Icons.phone,
                kind: ActionKind.outlined,
                onPressed: phoneRegistered ? () => dial(context, _elderPhone!) : null,
              ),
              if (!phoneRegistered) ...[
                const SizedBox(height: 8),
                const Text(
                  '프로필에서 전화번호를 등록하면 켜집니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.textSub),
                ),
              ],
              const SizedBox(height: 10),
              // 119 긴급 신고 — 이미 자동 신고된 이벤트면 잠근다
              ActionButton(
                label: '119 긴급 신고',
                icon: Icons.warning_amber,
                kind: ActionKind.emergency,
                onPressed: event.isReported119 ? null : () => dial(context, emergencyPhone),
              ),
              if (event.isReported119) ...[
                const SizedBox(height: 8),
                const Text(
                  '응답이 없어 119에 자동 신고되었습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 10),
              ActionButton(label: '확인', kind: ActionKind.primary, onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.textSub)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}
