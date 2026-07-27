// 스플래시 화면 — 딥 틸 배경에 로고, 1~2초 후 토큰 판단 결과로 분기

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.api, required this.onDone});

  final Api api;
  // 토큰 판단 후 호출. true면 로그인 됨, false면 시작 화면으로.
  final void Function(bool loggedIn) onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 최소 1.2초 노출 → 로고가 한 번 읽히도록. 동시에 토큰을 읽는다.
    const minDelay = Duration(milliseconds: 1200);
    final results = await Future.wait<dynamic>([widget.api.loadToken(), Future.delayed(minDelay)]);
    final token = results[0] as String?;
    if (!mounted) return;
    widget.onDone(token != null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 72),
          child: Column(
            children: [
              const Spacer(),
              brandLogo(),
              const SizedBox(height: 24),
              const Text(
                '낙상 알림',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  letterSpacing: -0.02,
                  color: AppColors.onPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '프라이버시 보존형 낙상 감지',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Color(0xC8FFFFFF),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// 스플래시와 시작 화면이 같은 로고 박스를 써 전환 때 배경만 바뀌고 로고는 제자리에 있다
Widget brandLogo() {
  return Container(
    width: 120,
    height: 120,
    decoration: BoxDecoration(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(36),
    ),
    child: const Icon(Icons.shield_outlined, size: 60, color: AppColors.primary),
  );
}
