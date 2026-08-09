// 전화 발신 공용 헬퍼 — 알림 상세 화면과 사고 발생 창이 같이 쓴다

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 119 신고용 번호 — 시연용 상수다. 실제 번호로 바꾸는 날 고칠 곳은 여기 하나다.
const emergencyPhone = '01000000119';

/// [number]로 전화 앱을 연다. 못 열면(미지원 환경·전화 앱 없음·플러그인 예외)
/// "전화 앱을 열 수 없습니다." 스낵바를 띄운다.
Future<void> dial(BuildContext context, String number) async {
  // async 갭 이전에 메신저를 잡아 두면 부른 위젯이 먼저 사라져도 안전하다
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri(scheme: 'tel', path: number);
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false; // launchUrl은 환경에 따라 false 대신 예외를 던지기도 한다
  }
  if (!ok) {
    messenger.showSnackBar(const SnackBar(content: Text('전화 앱을 열 수 없습니다.')));
  }
}
