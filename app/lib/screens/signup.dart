// 보호자 회원가입 화면 — 가입 성공 시 바로 MainShell로 들어간다

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_theme.dart';
import 'main_shell.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.api});

  final Api api;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text != _confirm.text) {
      setState(() => _error = '비밀번호가 서로 다릅니다.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.signup(_username.text, _password.text);
      if (!mounted) return;
      // 로그인 화면까지 스택에서 걷어내 뒤로 가기로 되돌아가지 않게 한다
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
              const Text('회원가입', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              // 규칙 안내 — 칸 위에 두어 다 치고 나서 읽는 경고가 아니라 치기 전 읽는 안내
              const Text(
                '비밀번호는 영문자, 숫자, 특수기호를 섞어 8자 이상으로 만들어주세요.',
                style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSub),
              ),
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
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: '비밀번호 확인'),
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
                    : const Text('가입하기'),
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
