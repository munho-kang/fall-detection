// Push.active 플래그의 초기값 계약 검증 (Firebase 플러그인 목킹 없이 가능한 범위만)
import 'package:fall_guardian/push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FCM 등록이 성공하기 전에는 기본적으로 비활성 상태다', () {
    expect(Push.active, isFalse);
  });
}
