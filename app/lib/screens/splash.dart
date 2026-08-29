// 스플래시 화면 — 초록 그라데이션 배경에 로고, 1~2초 후 토큰 판단 결과로 분기

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../widgets.dart';

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
      body: HeroBackground(
        child: SafeArea(
          // Scaffold body는 가로 constraints를 느슨하게 준다 — 기본 center 정렬만 믿으면
          // Column이 가장 넓은 자식 폭으로 수축해 화면 왼쪽에 붙는다. stretch + textAlign 조합으로 폭을 채운다.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(child: brandLogo()),
              const SizedBox(height: 24),
              const Text(
                '낙상 알림',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: -0.5,
                  color: AppColors.onPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '프라이버시 보존형 낙상 감지',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xCCFFFFFF)),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
