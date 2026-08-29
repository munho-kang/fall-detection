// flutter drive 드라이버 — 통합 테스트가 찍은 스크린샷을 docs/screenshots/<이름>.png로 저장한다.
// 실행 위치는 app/ 이다(상대 경로 ../docs/screenshots).

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final file = File('../docs/screenshots/$name.png');
        await file.writeAsBytes(bytes);
        return true;
      },
    );
