// API 호출 타임아웃 테스트 — 응답 없는 요청 1개가 폴링·화면을 무기한 잡아두면 안 된다

import 'dart:async';

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
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

  // baseUrl 분기 — 웹 지원으로 dart:io Platform을 걷어내면서 분기가 전부 주입 가능해졌다
  group('resolveBaseUrl', () {
    test('API_HOST가 지정되면 플랫폼과 무관하게 그 호스트다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '192.168.0.5',
          isWeb: true,
          pageUri: Uri.parse('http://192.168.0.7:8080/'),
          platform: TargetPlatform.android,
        ),
        'http://192.168.0.5:8000',
      );
    });

    test('웹은 페이지를 연 호스트가 곧 API 호스트다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: true,
          pageUri: Uri.parse('http://192.168.0.7:8080/index.html'),
          platform: TargetPlatform.windows,
        ),
        'http://192.168.0.7:8000',
      );
    });

    test('웹인데 페이지 호스트가 비면(file:// 등) 127.0.0.1로 간다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: true,
          pageUri: Uri.parse('file:///C:/site/index.html'),
          platform: TargetPlatform.windows,
        ),
        'http://127.0.0.1:8000',
      );
    });

    test('Android 에뮬레이터에서 호스트는 10.0.2.2다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: false,
          pageUri: Uri(),
          platform: TargetPlatform.android,
        ),
        'http://10.0.2.2:8000',
      );
    });

    test('iOS 시뮬레이터·데스크톱은 127.0.0.1이다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: false,
          pageUri: Uri(),
          platform: TargetPlatform.iOS,
        ),
        'http://127.0.0.1:8000',
      );
    });

    test('웹이면 안드로이드 브라우저라도 페이지 호스트가 이긴다 — isWeb 검사가 플랫폼보다 먼저다', () {
      expect(
        Api.resolveBaseUrl(
          apiHostDefine: '',
          isWeb: true,
          pageUri: Uri.parse('http://192.168.0.7:8080/'),
          platform: TargetPlatform.android,
        ),
        'http://192.168.0.7:8000',
      );
    });
  });
}
