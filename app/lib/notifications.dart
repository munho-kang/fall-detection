// flutter_local_notifications 래퍼

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_store.dart';
import 'models.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();

  // 웹에는 이 플러그인의 구현이 없다(호출 시 MissingPluginException). 웹에서는 탭이
  // 열려 있는 동안 사고 발생 모달이 알림 역할을 하므로 OS 알림은 조용히 건너뛴다.
  // kIsWeb은 상수라 VM 테스트에서 웹 경로를 못 타 — 오버라이드를 열어 둔다.
  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get _isWeb => debugIsWebOverride ?? kIsWeb;

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
    if (_isWeb) return;
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
    if (_isWeb) return;
    final on = await isEnabled();
    if (!on) return;
    await _plugin.show(
      id: event.id,
      title: '${event.roomLabel}에서 낙상 감지',
      body: body(event),
      notificationDetails: details,
    );
  }

  // 설정 화면에서 끈 경우 로컬 알림도 보내지 않는다
  static Future<bool> isEnabled() async {
    return LocalStore.notificationsOn();
  }
}
