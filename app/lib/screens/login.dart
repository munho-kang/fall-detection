// 보호자 로그인 화면 — 시작 화면에서 진입. 본문 큰 제목 + 입력칸 두 개 + 버튼

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import 'main_shell.dart';
import 'signup.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});

  final Api api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.login(_username.text, _password.text);
      if (!mounted) return;
      // 스택을 전부 걷어낸다 — pushReplacement는 이 로그인 라우트만 바꿔서 아래의
      // 시작 화면이 남고, 로그인된 홈에 뒤로가기 화살표가 생긴다. 회원가입과 같은 방식.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainShell(api: widget.api)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('로그인', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              const Text('보호자 계정으로 들어가요', style: TextStyle(fontSize: 15, color: AppColors.textSub)),
              const SizedBox(height: 28),
              TextField(
                controller: _username,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '아이디'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '비밀번호'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Text('로그인'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SignupScreen(api: widget.api)),
                        ),
                child: const Text('계정이 없나요? 회원가입'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
