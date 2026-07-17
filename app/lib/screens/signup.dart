// 보호자 회원가입 화면 — 가입 성공 시 바로 낙상 목록으로 들어간다

import 'package:flutter/material.dart';

import '../api.dart';
import 'fall_list.dart';

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
        MaterialPageRoute(builder: (_) => FallListScreen(api: widget.api)),
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
      appBar: AppBar(title: const Text('회원가입')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: '아이디', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: '비밀번호 확인', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Text('8자 이상, 숫자만은 불가',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('가입하기'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
