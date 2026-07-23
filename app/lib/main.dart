// 앱 진입점 — 저장된 토큰 유무로 첫 화면을 정한다

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'notifications.dart';
import 'screens/fall_list.dart';
import 'screens/login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // FCM 준비. 실패(google-services.json 누락 등)해도 앱은 폴링만으로 동작해야 하므로 죽이지 않는다.
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase 초기화 실패 — 푸시 없이 계속한다. $e');
    }
  }
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
  bool _loading = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _api.loadToken().then((token) {
      setState(() {
        _loggedIn = token != null;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '낙상 알림',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4C8DFF), useMaterial3: true),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _loggedIn
              ? FallListScreen(api: _api)
              : LoginScreen(api: _api),
    );
  }
}
