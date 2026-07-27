// 보호자 회원가입 화면 — 가입 성공 시 바로 MainShell로 들어간다

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../api.dart';
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
        title: const Text('회원가입'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 72),
              // 규칙 안내 — 칸 위로 올려 다 치고 나서 읽는 경고가 아니라 치기 전 읽는 안내
              Text(
                '비밀번호는 영문자, 숫자, 특수기호를 섞어 8자 이상으로 만들어주세요.',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  letterSpacing: -0.02,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _buildField(_username, '아이디'),
              const SizedBox(height: 12),
              _buildField(_password, '비밀번호', obscure: true),
              const SizedBox(height: 12),
              _buildField(_confirm, '비밀번호 확인', obscure: true),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                    disabledForegroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Text('가입하기'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String placeholder, {bool obscure = false}) {
    return SizedBox(
      height: 60,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(fontSize: 17, height: 1.3, color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(fontSize: 17, color: Theme.of(context).colorScheme.outline),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }
}
