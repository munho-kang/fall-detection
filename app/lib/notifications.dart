// flutter_local_notifications 래퍼

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();

  // android/iOS 어느 쪽이든 null이면 그 플랫폼에서 예외도 로그도 없이 알림이 안 뜬다.
  // 조용히 실패하는 자리라 테스트가 붙잡는다.
  @visibleForTesting
  static const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    ),
  );

  @visibleForTesting
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'fall_alerts',
      '낙상 알림',
      // 낙상은 헤드업으로 즉시 떠야 한다. 기본 중요도면 배너 없이 상태바에만 쌓인다.
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  static Future<void> init() async {
    await _plugin.initialize(settings: settings);
    // Android 13+는 런타임 권한이 따로 있다. 매니페스트 선언만으로는 알림이 안 뜬다.
    // iOS 권한은 위 DarwinInitializationSettings가 initialize 중에 요청한다.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // 알림 본문은 이벤트 상태에서 파생된다 — 괜찮음 응답이 도착한 뒤 같은 id로 다시 부르면
  // 트레이의 알림이 이 문구로 교체된다.
  @visibleForTesting
  static String body(FallEvent event) {
    final t = event.occurredAt;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return event.isVoiceOk
        ? '$time 발생 · 낙상자가 괜찮다고 말한 낙상 사고입니다'
        : '$time 발생 · 확인이 필요합니다';
  }

  static Future<void> show(FallEvent event) async {
    await _plugin.show(
      id: event.id,
      title: '${event.roomLabel}에서 낙상 감지',
      body: body(event),
      notificationDetails: details,
    );
  }
}
