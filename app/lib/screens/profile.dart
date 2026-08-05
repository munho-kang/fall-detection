// 프로필 창 (하단 탭) — 프로필 사진 · 내 정보 · 돌봄 대상자 정보 · 로그아웃 · 회원 탈퇴

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';
import '../local_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.api,
    required this.unreadCount,
    required this.onGoNotifications,
    required this.onGoSettings,
    required this.onLogout,
  });

  final Api api;
  final int unreadCount;
  final VoidCallback onGoNotifications;
  final VoidCallback onGoSettings;
  final VoidCallback onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _nickname;
  String? _contactPhone;
  String? _email;
  // 돌봄 대상자
  String? _caredPhone; // 백엔드 elderPhone
  String? _caredAddress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final nickname = await LocalStore.nickname();
    final contactPhone = await LocalStore.contactPhone();
    final email = await LocalStore.email();
    final caredAddress = await LocalStore.caredAddress();
    String? caredPhone;
    try {
      final p = await widget.api.getProfile();
      caredPhone = p.elderPhone;
    } catch (_) {
      caredPhone = '';
    }
    if (!mounted) return;
    setState(() {
      _nickname = nickname;
      _contactPhone = contactPhone;
      _email = email;
      _caredPhone = caredPhone;
      _caredAddress = caredAddress;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('프로필', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _avatar(),
                const SizedBox(height: 12),
                Text(
                  _nickname ?? '보호자님',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4),
                ),
                Text(
                  _contactPhone?.isNotEmpty == true ? _contactPhone! : '연락처 미등록',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                _sectionCard(
                  heading: '내 정보',
                  rows: [
                    _row('닉네임 변경', _nickname ?? '', () => _editNickname()),
                    _row('연락처 변경', _contactPhone?.isNotEmpty == true ? _contactPhone! : '', () => _editContactPhone()),
                    _row('이메일 변경', _email?.isNotEmpty == true ? _email! : '', () => _editEmail()),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  heading: '돌봄 대상자 정보',
                  rows: [
                    _row(
                      '전화번호',
                      _caredPhone == null
                          ? '불러오는 중'
                          : (_caredPhone!.isEmpty ? '미등록' : _caredPhone!),
                      valueColor: (_caredPhone?.isEmpty ?? false) ? AppColors.error : null,
                      () => _editCaredPhone(),
                    ),
                    _row('주소', _caredAddress ?? '', () => _editCaredAddress()),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  rows: [
                    _row('로그아웃', '', () => _confirmLogout(), trailingIcon: Icons.logout, dimText: false),
                    _row('회원 탈퇴', '', () => _confirmWithdraw(),
                        trailingIcon: Icons.delete_outline,
                        textColor: dangerColors(Theme.of(context).brightness).fg),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _avatar() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, size: 44, color: scheme.onPrimaryContainer),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  // 링은 페이지 배경을 오려낸 것처럼 보여야 한다 — 다크에서
                  // scaffoldBackgroundColor와 colorScheme.surface가 서로 다르다
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 16, color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({String? heading, required List<Widget> rows}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (heading != null)
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value,
    VoidCallback onTap, {
    IconData? trailingIcon,
    Color? textColor,
    Color? valueColor,
    bool dimText = true,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  color: textColor ?? Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: valueColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Icon(
              trailingIcon ?? Icons.chevron_right,
              size: 20,
              color: textColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNickname() => _editField(
        title: '닉네임 변경',
        value: _nickname ?? '',
        keyboardType: TextInputType.text,
        onSaved: (v) async {
          await LocalStore.setNickname(v);
          if (!mounted) return;
          setState(() => _nickname = v);
        },
      );

  Future<void> _editContactPhone() => _editField(
        title: '연락처 변경',
        value: _contactPhone ?? '',
        keyboardType: TextInputType.phone,
        onSaved: (v) async {
          await LocalStore.setContactPhone(v);
          if (!mounted) return;
          setState(() => _contactPhone = v);
        },
      );

  Future<void> _editEmail() => _editField(
        title: '이메일 변경',
        value: _email ?? '',
        keyboardType: TextInputType.emailAddress,
        onSaved: (v) async {
          await LocalStore.setEmail(v);
          if (!mounted) return;
          setState(() => _email = v);
        },
      );

  Future<void> _editCaredPhone() => _editField(
        title: '돌봄 대상자 전화번호',
        subtitle: '낙상 시 연락이 되는 번호입니다.',
        value: _caredPhone ?? '',
        keyboardType: TextInputType.phone,
        onSaved: (v) async {
          try {
            await widget.api.updateProfile(v);
            if (!mounted) return;
            setState(() => _caredPhone = v);
          } catch (e) {
            _snack(e.toString().replaceFirst('Exception: ', ''));
          }
        },
      );

  Future<void> _editCaredAddress() => _editField(
        title: '돌봄 대상자 주소',
        value: _caredAddress ?? '',
        keyboardType: TextInputType.text,
        onSaved: (v) async {
          await LocalStore.setCaredAddress(v);
          if (!mounted) return;
          setState(() => _caredAddress = v);
        },
      );

  Future<void> _editField({
    required String title,
    String? subtitle,
    required String value,
    required TextInputType keyboardType,
    required Future<void> Function(String) onSaved,
  }) async {
    // 입력값은 창이 pop할 때 결과로 받는다 — 컨트롤러는 창이 소유한다(_FieldEditDialog 주석).
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => _FieldEditDialog(
        title: title,
        subtitle: subtitle,
        value: value,
        keyboardType: keyboardType,
      ),
    );
    if (entered == null) return; // 취소
    await onSaved(entered.trim());
  }

  Future<void> _confirmLogout() async {
    // 로그아웃은 확인 없이 바로 처리
    widget.onLogout();
  }

  Future<void> _confirmWithdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final tone = dangerColors(Theme.of(context).brightness);
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          title: const Text('회원 탈퇴', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          content: Text(
            '계정과 알림 기록이 모두 삭제되며 되돌릴 수 없습니다. 정말 탈퇴하시겠어요?',
            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: tone.bg,
                foregroundColor: tone.fg,
              ),
              child: const Text('탈퇴'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    // 백엔드 탈퇴 endpoint가 없으므로 로컬 토큰/프로필만 삭제
    await LocalStore.clearProfile();
    // 다크모드/화면크기/알림 설정은 계정 설정이므로 유지
    widget.onLogout();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// 컨트롤러를 창이 소유해야 하는 이유: showDialog가 돌려주는 future는 pop 시점에 곧바로
// 완료되지만 라우트는 퇴장 애니메이션이 끝날 때까지 살아 있다. 호출부에서 future를
// 받자마자 dispose하면 그 사이 리빌드되는 TextField가 죽은 컨트롤러를 구독해
// "A TextEditingController was used after being disposed"로 터진다.
// State.dispose는 라우트가 언마운트될 때(=TextField가 사라진 뒤) 불려 안전하다.
class _FieldEditDialog extends StatefulWidget {
  const _FieldEditDialog({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.keyboardType,
  });

  final String title;
  final String? subtitle;
  final String value;
  final TextInputType keyboardType;

  @override
  State<_FieldEditDialog> createState() => _FieldEditDialogState();
}

class _FieldEditDialogState extends State<_FieldEditDialog> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      title: Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.subtitle!,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          TextField(
            controller: _controller,
            keyboardType: widget.keyboardType,
            decoration: const InputDecoration(
              border: UnderlineInputBorder(),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary, width: 2)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop<String>(context, _controller.text),
          child: const Text('저장'),
        ),
      ],
    );
  }
}
