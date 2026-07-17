// 폴링 응답에서 새 이벤트를 골라내는 로직과 5초 타이머

import 'dart:async';

import 'api.dart';
import 'models.dart';

class NewEventTracker {
  int? _lastSeenId;
  bool _primed = false;

  int? get lastSeenId => _lastSeenId;

  /// [events]는 서버가 준 최신순 목록이다. 마지막으로 본 id보다 큰 것만 새 이벤트다.
  /// 최초 호출(=로그인 직후)에는 기존 이벤트 알림 폭탄을 막기 위해 id만 저장하고 빈 목록을 준다.
  /// "최초 호출인가"는 id 저장 여부(`_lastSeenId == null`)와 별개로 `_primed`로 추적한다.
  /// 그래야 최초 응답이 마침 빈 목록이었던 경우에도, 그 다음 호출을 다시 최초 호출로
  /// 착각해 진짜 새 이벤트를 삼키지 않는다. 이 경우 lastSeenId는 아직 어떤 id도 보지
  /// 못했다는 뜻으로 null로 남는다.
  List<FallEvent> newEvents(List<FallEvent> events) {
    final isFirstCall = !_primed;
    _primed = true;

    if (events.isEmpty) return const [];

    final maxId = events.map((e) => e.id).reduce((a, b) => a > b ? a : b);

    if (isFirstCall) {
      _lastSeenId = maxId;
      return const [];
    }

    final fresh = _lastSeenId == null
        ? events
        : events.where((e) => e.id > _lastSeenId!).toList();
    _lastSeenId = maxId;
    return fresh;
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
  final void Function(List<FallEvent> all, List<FallEvent> fresh) onEvents;
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
      final fresh = _tracker.newEvents(all);
      if (_consecutiveFailures >= _failuresBeforeBanner) onRecovered();
      _consecutiveFailures = 0;
      onEvents(all, fresh);
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
