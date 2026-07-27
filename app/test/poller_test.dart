// 새 이벤트 판별 로직 단위 테스트

import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/poller.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent ev(int id, {DateTime? voiceOkAt}) => FallEvent(
      id: id,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 17, 12),
      createdAt: DateTime(2026, 7, 17, 12),
      confidence: 0.9,
      voiceOkAt: voiceOkAt,
    );

void main() {
  test('최초 응답은 알림 없이 id만 저장한다', () {
    final tracker = NewEventTracker();

    // 로그인 직후 기존 이벤트 전부에 알림이 쏟아지면 안 된다
    expect(tracker.newEvents([ev(3), ev(2), ev(1)]).fresh, isEmpty);
    expect(tracker.lastSeenId, 3);
  });

  test('같은 응답이 반복되면 새 이벤트가 없다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    expect(tracker.newEvents([ev(3), ev(2), ev(1)]).fresh, isEmpty);
  });

  test('새 이벤트 2건이 오면 2건만 돌려준다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    final fresh = tracker.newEvents([ev(5), ev(4), ev(3), ev(2), ev(1)]).fresh;

    expect(fresh.map((e) => e.id), [5, 4]);
    expect(tracker.lastSeenId, 5);
  });

  test('최초 응답이 비어 있으면 그 다음 첫 이벤트는 새 이벤트다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([]);

    expect(tracker.newEvents([ev(1)]).fresh.map((e) => e.id), [1]);
  });

  test('최초 응답의 괜찮음 이벤트는 newlyOk가 아니다', () {
    final tracker = NewEventTracker();

    // 로그인 직후 옛 괜찮음 이벤트로 알림 폭탄이 터지면 안 된다
    final delta = tracker.newEvents([ev(2, voiceOkAt: DateTime(2026, 7, 27, 12, 1)), ev(1)]);

    expect(delta.fresh, isEmpty);
    expect(delta.newlyOk, isEmpty);
  });

  test('이미 알린 이벤트에 괜찮음이 새로 붙으면 newlyOk로 정확히 1회 나온다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(1)]);
    tracker.newEvents([ev(1)]); // 프라이밍 뒤 한 번 더 — 아직 괜찮음 없음

    final delta = tracker.newEvents([ev(1, voiceOkAt: DateTime(2026, 7, 27, 12, 1))]);
    expect(delta.fresh, isEmpty);
    expect(delta.newlyOk.map((e) => e.id), [1]);

    // 다음 폴링에도 그대로 실려 오지만 다시 알리지 않는다
    final again = tracker.newEvents([ev(1, voiceOkAt: DateTime(2026, 7, 27, 12, 1))]);
    expect(again.newlyOk, isEmpty);
  });

  test('처음부터 괜찮음이 실려 온 새 이벤트는 fresh로만 나온다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(1)]);

    final delta = tracker.newEvents([ev(2, voiceOkAt: DateTime(2026, 7, 27, 12, 1)), ev(1)]);

    expect(delta.fresh.map((e) => e.id), [2]);
    expect(delta.newlyOk, isEmpty); // 첫 알림이 곧 괜찮음 문구다 — 두 번 뜨지 않는다
  });
}
