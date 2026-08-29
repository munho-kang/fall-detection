// 시작 화면 — 초록 히어로(로고 · 소개) 위, 로그인/회원가입 버튼 아래. 신규·로그인 진입의 첫 화면

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import '../widgets.dart';
import 'login.dart';
import 'signup.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.api});

  final Api api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 위: 남는 높이를 전부 차지하는 초록 히어로
          Expanded(
            child: HeroBackground(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      brandLogo(size: 72),
                      const SizedBox(height: 18),
                      const Text(
                        '낙상 알림',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: -0.5,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '돌봄 대상자의 낙상을 감지해\n보호자에게 실시간으로 알려드립니다.',
                        style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xEBFFFFFF)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 아래: 버튼 둘 + 사생활 한 줄. 자연 높이만 차지한다
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // tall 버튼(56dp). 손이 큰 사용자도 정확히 누르도록
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LoginScreen(api: api)),
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
                        side: const BorderSide(color: AppColors.primaryTint, width: 1.5),
                      ),
                      child: const Text('회원가입'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
                      SizedBox(width: 5),
                      Text('영상은 집 밖으로 나가지 않아요', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
