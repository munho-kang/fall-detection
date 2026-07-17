// 폴링 응답에서 새 이벤트를 골라내는 로직과 5초 타이머

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
