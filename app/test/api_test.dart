// API 호출 타임아웃 테스트 — 응답 없는 요청 1개가 폴링·화면을 무기한 잡아두면 안 된다

import 'dart:async';

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 응답을 영원히 주지 않는 서버. 와이파이가 끊기는 순간의 매달린 요청을 재현한다.
Api hungApi() => Api(client: MockClient((_) => Completer<http.Response>().future));

void main() {
  testWidgets('서버가 응답하지 않으면 listFalls가 5초 뒤 한국어 예외로 끝난다', (tester) async {
    final api = hungApi();

    Object? error;
    unawaited(api.listFalls().then<void>((_) {}, onError: (Object e) => error = e));

    await tester.pump(const Duration(seconds: 4));
    expect(error, isNull, reason: '느린 응답은 기다려야 한다 — 타임아웃은 5초다');

    await tester.pump(const Duration(seconds: 2));
    expect(error, isNotNull, reason: '매달린 요청은 무기한 대기 대신 예외로 끝나야 한다');
    // 화면이 e.toString()을 그대로 보여주므로 영어 TimeoutException이 노출되면 안 된다
    expect(error.toString(), contains('서버가 응답하지'));
  });

  testWidgets('acknowledge도 응답이 없으면 타임아웃으로 끝난다', (tester) async {
    final api = hungApi();

    Object? error;
    unawaited(api.acknowledge(1).then<void>((_) {}, onError: (Object e) => error = e));

    await tester.pump(const Duration(seconds: 6));
    expect(error, isNotNull, reason: '조회뿐 아니라 쓰기 호출에도 타임아웃이 걸려야 한다');
  });

  testWidgets('제때 온 응답은 타임아웃과 무관하게 그대로 처리된다', (tester) async {
    final api = Api(client: MockClient((_) async => http.Response('[]', 200)));

    List<FallEvent>? result;
    unawaited(api.listFalls().then((r) => result = r));
    await tester.pump();

    expect(result, isEmpty);
  });
}
