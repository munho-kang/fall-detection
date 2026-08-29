// 설정 창 — 앱 설정(화면 크기 · 알림) + 지원 및 정보

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../local_store.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TextScale _textScale = TextScale.normal;
  bool _notificationsOn = true;
  bool _loading = true;
  bool _showNotifWarning = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scale = await LocalStore.textScale();
    final notif = await LocalStore.notificationsOn();
    if (!mounted) return;
    setState(() {
      _textScale = scale;
      _notificationsOn = notif;
      _loading = false;
    });
  }

  Future<void> _setTextScale(TextScale scale) async {
    await LocalStore.setTextScale(scale);
    setState(() => _textScale = scale);
  }

  Future<void> _setNotificationsOn(bool on) async {
    await LocalStore.setNotificationsOn(on);
    setState(() {
      _notificationsOn = on;
      _showNotifWarning = !on;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('설정'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                _sectionCard(
                  heading: '앱 설정',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('화면 크기', style: TextStyle(fontSize: 17)),
                      trailing: _textScaleSeg(),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _notificationsOn,
                      onChanged: _setNotificationsOn,
                      title: const Text('알림 설정', style: TextStyle(fontSize: 17)),
                    ),
                  ],
                ),
                if (_showNotifWarning) ...[
                  const SizedBox(height: 16),
                  const NoticeBanner(text: '알림을 끄면 낙상 알림이 더이상 가지 않습니다.'),
                ],
                const SizedBox(height: 16),
                _sectionCard(
                  heading: '지원 및 정보',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('공지사항', style: TextStyle(fontSize: 17)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () => _snack('준비 중입니다'),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('문의하기', style: TextStyle(fontSize: 17)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () => _snack('준비 중입니다'),
                    ),
                    const Divider(),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('앱 버전', style: TextStyle(fontSize: 17)),
                      trailing: Text('MVP v1.0', style: TextStyle(fontSize: 15, color: AppColors.textSub)),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // 작게 · 보통 · 크게 — 연회색 알약 안에서 선택 칸만 초록 틴트
  Widget _textScaleSeg() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in TextScale.values)
            InkWell(
              onTap: () => _setTextScale(s),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: _textScale == s
                    ? BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(999))
                    : null,
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _textScale == s ? FontWeight.w700 : FontWeight.w400,
                    color: _textScale == s ? AppColors.primary : AppColors.textSub,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String heading, required List<Widget> children}) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(heading, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textSub)),
          ),
          ...children,
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
