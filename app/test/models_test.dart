// 서버 JSON → FallEvent 파싱 검증 — reported_119_at·voice_ok_at 유무

import 'package:fall_guardian/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = <String, dynamic>{
    'id': 1,
    'room_name': '안방',
    'room_number': 1,
    'occurred_at': '2026-07-27T03:00:00Z',
    'created_at': '2026-07-27T03:00:05Z',
    'confidence': 0.9,
    'acknowledged_at': null,
  };

  test('reported_119_at 키가 아예 없으면(구버전 응답) 신고 안 된 상태다', () {
    final e = FallEvent.fromJson(base);

    expect(e.reported119At, isNull);
    expect(e.isReported119, isFalse);
  });

  test('reported_119_at이 있으면 로컬 시각으로 파싱되고 신고 상태다', () {
    final e = FallEvent.fromJson({...base, 'reported_119_at': '2026-07-27T03:00:20Z'});

    expect(e.isReported119, isTrue);
    expect(e.reported119At, DateTime.parse('2026-07-27T03:00:20Z').toLocal());
  });

  test('voice_ok_at 키가 아예 없으면 괜찮음 응답이 없는 상태다', () {
    final e = FallEvent.fromJson(base);

    expect(e.voiceOkAt, isNull);
    expect(e.isVoiceOk, isFalse);
  });

  test('voice_ok_at이 있으면 로컬 시각으로 파싱되고 괜찮음 상태다', () {
    final e = FallEvent.fromJson({...base, 'voice_ok_at': '2026-07-27T03:00:12Z'});

    expect(e.isVoiceOk, isTrue);
    expect(e.voiceOkAt, DateTime.parse('2026-07-27T03:00:12Z').toLocal());
  });
}
