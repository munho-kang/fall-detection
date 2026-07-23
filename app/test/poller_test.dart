// 새 이벤트 판별 로직 단위 테스트

import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/poller.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent ev(int id) => FallEvent(
      id: id,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 17, 12),
      createdAt: DateTime(2026, 7, 17, 12),
      confidence: 0.9,
    );

void main() {
  test('최초 응답은 알림 없이 id만 저장한다', () {
    final tracker = NewEventTracker();

    // 로그인 직후 기존 이벤트 전부에 알림이 쏟아지면 안 된다
    expect(tracker.newEvents([ev(3), ev(2), ev(1)]), isEmpty);
    expect(tracker.lastSeenId, 3);
  });

  test('같은 응답이 반복되면 새 이벤트가 없다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    expect(tracker.newEvents([ev(3), ev(2), ev(1)]), isEmpty);
  });

  test('새 이벤트 2건이 오면 2건만 돌려준다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    final fresh = tracker.newEvents([ev(5), ev(4), ev(3), ev(2), ev(1)]);

    expect(fresh.map((e) => e.id), [5, 4]);
    expect(tracker.lastSeenId, 5);
  });

  test('최초 응답이 비어 있으면 그 다음 첫 이벤트는 새 이벤트다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([]);

    expect(tracker.newEvents([ev(1)]).map((e) => e.id), [1]);
  });

  test('Android에서는 폴링 새 이벤트로 알리지 않는다 — 알림은 FCM 한 소스에서만 온다', () {
    expect(notifiableFromPolling([ev(2), ev(1)], isAndroid: true), isEmpty);
  });

  test('iOS에서는 FCM이 없으므로 폴링 새 이벤트가 그대로 알림 대상이다', () {
    expect(notifiableFromPolling([ev(2), ev(1)], isAndroid: false).map((e) => e.id), [2, 1]);
  });
}
