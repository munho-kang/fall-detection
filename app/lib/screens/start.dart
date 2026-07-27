// 시작 화면 — 로고 · 소개 멘트 · 로그인/회원가입 버튼. 신규·로그인 진입의 첫 화면

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';
import 'login.dart';
import 'signup.dart';
import 'splash.dart' show brandLogo;

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.api});

  final Api api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 72),
              Center(child: brandLogo()),
              const SizedBox(height: 24),
              const Text(
                '낙상 알림',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  letterSpacing: -0.02,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '돌봄 대상자의 낙상을 감지해\n보호자에게 실시간으로 알려드립니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 36),
              // tall 버튼(56dp). 손이 큰 사용자도 정확히 누르도록
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LoginScreen(api: api)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('로그인'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SignupScreen(api: api)),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.outline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('회원가입'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
