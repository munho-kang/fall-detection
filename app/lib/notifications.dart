// flutter_local_notifications 래퍼

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _details = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  static Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );
  }

  static Future<void> show(FallEvent event) async {
    final t = event.occurredAt;
    await _plugin.show(
      id: event.id,
      title: '${event.roomLabel}에서 낙상 감지',
      body: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} 발생 · 확인이 필요합니다',
      notificationDetails: _details,
    );
  }
}
