// Android FCM 등록·해제와 포그라운드 수신 (Android 전용 — iOS 앱은 폴링만 쓴다)

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'api.dart';
import 'models.dart';
import 'notifications.dart';

class Push {
  // 로그아웃 → 재로그인을 반복해도 스트림 리스너는 한 번만 건다.
  static bool _wired = false;

  // FCM 토큰 취득 + 서버 등록이 모두 성공했을 때만 true. false면 폴링 알림이 백업으로 켜진다.
  static bool active = false;

  /// 로그인 상태에서 호출한다. FCM 토큰을 서버에 등록하고 토큰 갱신·포그라운드 수신을 구독한다.
  /// 푸시는 부가 기능이고 폴링이 항상 백업이므로, 실패해도 절대 던지지 않는다.
  static Future<void> register(Api api) async {
    if (!Platform.isAndroid) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await api.registerPushDevice(token);
        active = true;
      }

      if (!_wired) {
        _wired = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((t) {
          // 로그아웃 상태에서 갱신되면 401로 실패하지만, 다음 로그인의 register가 다시 등록한다.
          api.registerPushDevice(t).catchError((e) => debugPrint('토큰 갱신 등록 실패. $e'));
        });
        // 포그라운드에서는 OS가 notification부를 표시하지 않으므로 data부로 직접 띄운다.
        // 알림 id=이벤트 id라 어떤 경로로든 같은 낙상은 알림 1개로 합쳐진다.
        FirebaseMessaging.onMessage.listen(_showForeground);
      }
    } catch (e) {
      debugPrint('FCM 등록 실패 — 폴링만으로 동작한다. $e');
    }
  }

  /// 로그아웃 직전에 호출한다. 이 기기의 토큰을 서버에서 지워 로그아웃 뒤 알림을 막는다.
  static Future<void> unregister(Api api) async {
    if (!Platform.isAndroid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await api.deletePushDevice(token);
    } catch (e) {
      // 실패해도 로그아웃은 진행한다. 죽은 토큰은 다음 발송 때 서버가 정리한다.
      debugPrint('푸시 기기 해제 실패. $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final d = message.data;
    if (d['type'] != 'fall') return;
    final id = int.tryParse('${d['id']}');
    final occurredAt = DateTime.tryParse('${d['occurred_at']}');
    if (id == null || occurredAt == null) return;
    await Notifications.show(FallEvent(
      id: id,
      roomName: '${d['room_name'] ?? ''}',
      roomNumber: int.tryParse('${d['room_number']}') ?? 0,
      occurredAt: occurredAt.toLocal(),
      createdAt: occurredAt.toLocal(),
      confidence: double.tryParse('${d['confidence']}') ?? 0,
    ));
  }
}
