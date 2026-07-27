// 알림 설정이 두 플랫폼 모두 채워져 있는지 — 비면 그 플랫폼에서 조용히 안 뜬다

import 'package:fall_guardian/notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 초기화 설정이 채워져 있다', () {
    expect(Notifications.settings.android, isNotNull);
    expect(Notifications.settings.android!.defaultIcon, '@mipmap/ic_launcher');
  });

  test('Android 알림은 헤드업으로 뜬다', () {
    final android = Notifications.details.android;

    expect(android, isNotNull);
    expect(android!.channelId, 'fall_alerts');
    expect(android.channelName, '낙상 알림');
    expect(android.importance, Importance.max);
    expect(android.priority, Priority.high);
  });

  test('iOS 설정은 그대로다', () {
    final settings = Notifications.settings.iOS;
    final details = Notifications.details.iOS;

    expect(settings, isNotNull);
    expect(settings!.requestAlertPermission, isTrue);
    expect(settings.requestBadgePermission, isTrue);
    expect(settings.requestSoundPermission, isTrue);

    expect(details, isNotNull);
    expect(details!.presentAlert, isTrue);
    expect(details.presentBadge, isTrue);
    expect(details.presentSound, isTrue);
  });
}
