// 입력칸이 있는 다이얼로그(방 추가·수정, 프로필 항목 변경)의 컨트롤러 수명 —
// showDialog의 future는 pop 시점에 완료되지만 라우트는 퇴장 애니메이션 동안 살아 있다.
// 호출부에서 곧바로 dispose하면 그 사이 리빌드되는 TextField가 죽은 컨트롤러를 구독해 터진다.

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/profile.dart';
import 'package:fall_guardian/screens/room_management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends Api {
  final created = <String>[];
  final renamed = <String>[];

  @override
  Future<List<Room>> listRooms() async => const [];

  @override
  Future<Profile> getProfile() async => const Profile(elderPhone: '');

  @override
  Future<Room> createRoom(String name, int number) async {
    created.add('$name/$number');
    return Room(id: 9, name: name, number: number);
  }

  @override
  Future<Room> renameRoom(int id, String name, int number) async {
    renamed.add('$id:$name/$number');
    return Room(id: id, name: name, number: number);
  }
}

Future<void> _pumpRooms(WidgetTester tester, _FakeApi api, {List<Room> rooms = const []}) async {
  await tester.pumpWidget(MaterialApp(
    home: RoomManagementScreen(
      api: api,
      rooms: rooms,
      loading: false,
      reload: () async {},
      unreadCount: 0,
      onGoNotifications: () {},
      onGoSettings: () {},
    ),
  ));
}

Future<void> _pumpProfile(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(MaterialApp(
    home: ProfileScreen(
      api: api,
      unreadCount: 0,
      onGoNotifications: () {},
      onGoSettings: () {},
      onLogout: () {},
    ),
  ));
  await tester.pump(); // _load()의 비동기 응답
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('방 추가·수정 창', () {
    testWidgets('취소로 닫아도 예외가 없다', (tester) async {
      final api = _FakeApi();
      await _pumpRooms(tester, api);

      await tester.tap(find.text('방 추가'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(api.created, isEmpty);
    });

    testWidgets('저장으로 닫아도 예외 없이 방이 만들어진다', (tester) async {
      final api = _FakeApi();
      await _pumpRooms(tester, api);

      await tester.tap(find.text('방 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '안방');
      await tester.enterText(find.byType(TextField).last, '4');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.created, ['안방/4']);
    });

    testWidgets('수정 창은 기존 이름·번호가 채워져 있고 저장하면 그 값이 나간다', (tester) async {
      final api = _FakeApi();
      await _pumpRooms(tester, api, rooms: const [Room(id: 3, name: '거실', number: 1)]);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('방 수정'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller?.text, '거실');
      expect(tester.widget<TextField>(find.byType(TextField).last).controller?.text, '1');

      await tester.enterText(find.byType(TextField).first, '큰방');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.renamed, ['3:큰방/1']);
    });

    testWidgets('이름이 비면 저장해도 방을 만들지 않고 안내만 띄운다', (tester) async {
      final api = _FakeApi();
      await _pumpRooms(tester, api);

      await tester.tap(find.text('방 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '4');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.created, isEmpty);
      expect(find.text('이름과 숫자 번호를 모두 입력하세요.'), findsOneWidget);
    });
  });

  group('프로필 항목 변경 창', () {
    testWidgets('취소로 닫아도 예외가 없다', (tester) async {
      await _pumpProfile(tester, _FakeApi());

      await tester.tap(find.text('닉네임 변경'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('저장으로 닫아도 예외 없이 값이 반영된다', (tester) async {
      await _pumpProfile(tester, _FakeApi());

      await tester.tap(find.text('닉네임 변경'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '보호자님');

      await tester.enterText(find.byType(TextField), '홍길동');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('홍길동'), findsWidgets);
    });
  });
}
