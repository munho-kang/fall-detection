// 설정 창 — 앱 설정(다크모드 · 화면 크기 · 알림) + 지원 및 정보

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../local_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 다크모드 — auto(true)면 시스템 따라감. false면 _darkMode 값 사용
  bool _darkMode = false;
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
    final auto = await LocalStore.isDarkModeAuto();
    final dark = await LocalStore.isDarkMode();
    final scale = await LocalStore.textScale();
    final notif = await LocalStore.notificationsOn();
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    if (!mounted) return;
    setState(() {
      // auto 모드면 시스템 밝기를 표시, 아니면 저장된 값을 표시
      _darkMode = auto ? platformDark : dark;
      _textScale = scale;
      _notificationsOn = notif;
      _loading = false;
    });
  }

  // 시스템 다크모드 여부 — MaterialApp이 themeMode로 처리하므로 여기서는
  // SharedPreferences에 쓰기만 한다. main.dart는 설정 화면에서 돌아오면
  // prefs를 다시 읽어(themeMode · textScaler) 즉시 반영한다.
  Future<void> _setDarkMode(bool dark) async {
    await LocalStore.setDarkMode(dark);
    setState(() => _darkMode = dark);
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
        title: const Text('설정', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard(
                  heading: '앱 설정',
                  children: [
                    SwitchListTile(
                      value: _darkMode,
                      onChanged: _setDarkMode,
                      title: const Text(
                        '다크모드',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400),
                      ),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant, indent: 0, endIndent: 0),
                    ListTile(
                      title: const Text('화면 크기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
                      trailing: _textScaleSeg(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    SwitchListTile(
                      value: _notificationsOn,
                      onChanged: _setNotificationsOn,
                      title: const Text('알림 설정', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
                    ),
                  ],
                ),
                if (_showNotifWarning) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '알림을 끄면 낙상 알림이 더이상 가지 않습니다.',
                            style: TextStyle(
                              fontSize: 12 * (_textScale.factor),
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              letterSpacing: -0.01,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _sectionCard(
                  heading: '지원 및 정보',
                  children: [
                    ListTile(
                      title: const Text('공지사항', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
                      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onTap: () => _snack('준비 중입니다'),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    ListTile(
                      title: const Text('문의하기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
                      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onTap: () => _snack('준비 중입니다'),
                    ),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    ListTile(
                      title: const Text('앱 버전', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
                      trailing: Text(
                        'MVP v1.0',
                        style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _textScaleSeg() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < TextScale.values.length; i++) ...[
            InkWell(
              onTap: () => _setTextScale(TextScale.values[i]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                height: 36,
                alignment: Alignment.center,
                decoration: _textScale == TextScale.values[i]
                    ? BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.horizontal(
                          left: i == 0 ? const Radius.circular(20) : Radius.zero,
                          right: i == TextScale.values.length - 1 ? const Radius.circular(20) : Radius.zero,
                        ),
                      )
                    : null,
                child: Text(
                  TextScale.values[i].label,
                  style: TextStyle(
                    fontSize: 13,
                    color: _textScale == TextScale.values[i]
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: _textScale == TextScale.values[i] ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            if (i < TextScale.values.length - 1)
              SizedBox(width: 1, child: SizedBox(height: 24, child: VerticalDivider(color: Theme.of(context).colorScheme.outline))),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({required String heading, required List<Widget> children}) {
    // ListTile·SwitchListTile은 가장 가까운 Material에 그린다 — 색 있는 Container로 감싸면
    // 디버그 검증이 예외를 던지므로 알림 목록 카드처럼 Material을 쓴다.
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(
                heading,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
