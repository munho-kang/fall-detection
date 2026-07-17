// 앱 진입점 — 저장된 토큰 유무로 첫 화면을 정한다

import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/fall_list.dart';
import 'screens/login.dart';

void main() {
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
