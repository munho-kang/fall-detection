// 앱 진입점 — 설정(화면 크기)을 읽어 ThemeData에 반영하고 스플래시로 분기. 테마는 라이트 하나뿐이다

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

class _FallGuardianAppState extends State<FallGuardianApp> {
  final _api = Api();
  bool _loadingPrefs = true;
  TextScale _scale = TextScale.normal;
  // 인증 흐름 단계 — 스플래시 끝나면 true, 그 전엔 스플래시 표시
  bool _bootDone = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final scale = await LocalStore.textScale();
    if (!mounted) return;
    setState(() {
      _scale = scale;
      _loadingPrefs = false;
    });
  }

  // 설정 화면에서 돌아오면 prefs를 다시 읽어 배율을 즉시 반영
  void _onSettingsResume() {
    _loadPrefs();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    // darkTheme을 주지 않으므로 기기가 다크모드여도 항상 theme(라이트)로 그린다
    return MaterialApp(
      title: '낙상 알림',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(scale: _scale),
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
