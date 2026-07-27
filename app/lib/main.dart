// 앱 진입점 — 설정(다크모드·화면 크기)을 읽어 ThemeData에 반영하고 스플래시로 분기

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'api.dart';
import 'local_store.dart';
import 'notifications.dart';
import 'screens/main_shell.dart';
import 'screens/splash.dart';
import 'screens/start.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  runApp(const FallGuardianApp());
}

class FallGuardianApp extends StatefulWidget {
  const FallGuardianApp({super.key});

  @override
  State<FallGuardianApp> createState() => _FallGuardianAppState();
}

class _FallGuardianAppState extends State<FallGuardianApp> with WidgetsBindingObserver {
  final _api = Api();
  bool _loadingPrefs = true;
  bool _darkAuto = true;
  bool _dark = false;
  TextScale _scale = TextScale.normal;
  // 인증 흐름 단계 — 스플래시 끝나면 true, 그 전엔 스플래시 표시
  bool _bootDone = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_darkAuto && !_loadingPrefs) {
      setState(() {});
    }
  }

  Future<void> _loadPrefs() async {
    final auto = await LocalStore.isDarkModeAuto();
    final dark = await LocalStore.isDarkMode();
    final scale = await LocalStore.textScale();
    if (!mounted) return;
    setState(() {
      _darkAuto = auto;
      _dark = dark;
      _scale = scale;
      _loadingPrefs = false;
    });
  }

  // 설정 화면에서 돌아오면 prefs를 다시 읽어 다크모드·배율을 즉시 반영
  void _onSettingsResume() {
    _loadPrefs();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    final platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final effectiveDark = _darkAuto ? platformBrightness == Brightness.dark : _dark;
    return MaterialApp(
      title: '낙상 알림',
      debugShowCheckedModeBanner: false,
      themeMode: effectiveDark ? ThemeMode.dark : ThemeMode.light,
      theme: buildAppTheme(dark: false, scale: _scale),
      darkTheme: buildAppTheme(dark: true, scale: _scale),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_bootDone) {
      return SplashScreen(
        api: _api,
        onDone: (loggedIn) {
          setState(() {
            _loggedIn = loggedIn;
            _bootDone = true;
          });
        },
      );
    }
    if (_loggedIn) {
      return MainShell(api: _api, onSettingsResume: _onSettingsResume);
    }
    return StartScreen(api: _api);
  }
}
