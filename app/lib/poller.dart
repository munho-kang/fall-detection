// 폴링 응답에서 새 이벤트를 골라내는 로직과 5초 타이머

import 'dart:async';

import 'api.dart';
import 'models.dart';

/// 폴링 1회분의 알림 대상. fresh는 처음 보는 이벤트, newlyOk는 이미 알린 이벤트에
/// 괜찮음 응답이 새로 도착한 것 — 같은 id로 알림을 다시 띄워 문구를 교체한다.
typedef PollDelta = ({List<FallEvent> fresh, List<FallEvent> newlyOk});

class NewEventTracker {
  int? _lastSeenId;
  bool _primed = false;
  final Set<int> _okSeen = {}; // 괜찮음을 이미 반영해 알린(또는 프라이밍한) 이벤트 id

  int? get lastSeenId => _lastSeenId;

  /// [events]는 서버가 준 최신순 목록이다. 마지막으로 본 id보다 큰 것만 새 이벤트다.
  /// 최초 호출(=로그인 직후)에는 기존 이벤트 알림 폭탄을 막기 위해 id만 저장하고 빈 결과를 준다.
  /// "최초 호출인가"는 id 저장 여부(`_lastSeenId == null`)와 별개로 `_primed`로 추적한다.
  /// 그래야 최초 응답이 마침 빈 목록이었던 경우에도, 그 다음 호출을 다시 최초 호출로
  /// 착각해 진짜 새 이벤트를 삼키지 않는다. 이 경우 lastSeenId는 아직 어떤 id도 보지
  /// 못했다는 뜻으로 null로 남는다.
  /// newlyOk는 이미 알린 이벤트 중 괜찮음이 이번에 처음 보인 것이다. fresh와 겹치지 않는다 —
  /// 처음부터 괜찮음이 실려 온 새 이벤트는 첫 알림이 곧 괜찮음 문구라 fresh로만 나간다.
  PollDelta newEvents(List<FallEvent> events) {
    final isFirstCall = !_primed;
    _primed = true;

    if (events.isEmpty) return (fresh: const [], newlyOk: const []);

    final maxId = events.map((e) => e.id).reduce((a, b) => a > b ? a : b);
    final okIds = events.where((e) => e.isVoiceOk).map((e) => e.id);

    if (isFirstCall) {
      _lastSeenId = maxId;
      _okSeen.addAll(okIds);
      return (fresh: const [], newlyOk: const []);
    }

    final fresh = _lastSeenId == null
        ? events
        : events.where((e) => e.id > _lastSeenId!).toList();
    final freshIds = fresh.map((e) => e.id).toSet();
    final newlyOk = events
        .where((e) => e.isVoiceOk && !_okSeen.contains(e.id) && !freshIds.contains(e.id))
        .toList();
    _lastSeenId = maxId;
    _okSeen.addAll(okIds);
    return (fresh: fresh, newlyOk: newlyOk);
  }
}

class FallPoller {
  FallPoller({
    required this.api,
    required this.onEvents,
    required this.onConnectionLost,
    required this.onRecovered,
    required this.onUnauthorized,
  });

  static const _interval = Duration(seconds: 5);
  static const _failuresBeforeBanner = 3;

  final Api api;
  final void Function(List<FallEvent> all, List<FallEvent> fresh, List<FallEvent> newlyOk)
      onEvents;
  final void Function() onConnectionLost;
  final void Function() onRecovered;
  final void Function() onUnauthorized;

  final _tracker = NewEventTracker();
  Timer? _timer;
  int _consecutiveFailures = 0;
  bool _inFlight = false;

  void start() {
    _tick();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    // 이전 요청이 아직 끝나지 않았는데 새 틱이 또 요청을 보내면, 응답이 엇갈려 도착할 때
    // (나중에 보낸 요청이 먼저 응답) _lastSeenId가 더 오래된 값으로 되돌아가
    // 이미 알린 낙상을 다시 알릴 수 있다. 그래서 이전 요청이 끝날 때까지 새 틱은 건너뛴다.
    if (_inFlight) return;
    _inFlight = true;
    try {
      final all = await api.listFalls();
      final delta = _tracker.newEvents(all);
      if (_consecutiveFailures >= _failuresBeforeBanner) onRecovered();
      _consecutiveFailures = 0;
      onEvents(all, delta.fresh, delta.newlyOk);
    } on UnauthorizedException {
      stop();
      onUnauthorized();
    } catch (_) {
      // 조용히 다음 주기에 재시도한다. 3회 연속 실패해야 사용자에게 알린다.
      _consecutiveFailures += 1;
      if (_consecutiveFailures == _failuresBeforeBanner) onConnectionLost();
    } finally {
      _inFlight = false;
    }
  }
}
