// SharedPreferences 래퍼 — 화면 크기·알림 설정·프로필 로컬 필드 보관

import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart' show TextScale;

class LocalStore {
  const LocalStore._();

  static const _kTextScale = 'local.text_scale';
  static const _kNotificationsOn = 'local.notifications_on';

  // 프로필 로컬 필드 — 백엔드 확장 전까지 앱 안에서 보관
  static const _kNickname = 'local.profile.nickname';
  static const _kContactPhone = 'local.profile.contact_phone';
  static const _kEmail = 'local.profile.email';
  static const _kCaredName = 'local.profile.cared_name';
  static const _kCaredAddress = 'local.profile.cared_address';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _instance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // 화면 크기
  static Future<TextScale> textScale() async {
    final p = await _instance();
    final idx = p.getInt(_kTextScale) ?? TextScale.normal.index;
    return TextScale.values[idx.clamp(0, TextScale.values.length - 1)];
  }

  static Future<void> setTextScale(TextScale scale) async {
    final p = await _instance();
    await p.setInt(_kTextScale, scale.index);
  }

  // 알림 설정
  static Future<bool> notificationsOn() async {
    final p = await _instance();
    return p.getBool(_kNotificationsOn) ?? true;
  }

  static Future<void> setNotificationsOn(bool on) async {
    final p = await _instance();
    await p.setBool(_kNotificationsOn, on);
  }

  // 프로필 로컬 필드
  static Future<String> nickname() async {
    final p = await _instance();
    return p.getString(_kNickname) ?? '보호자님';
  }

  static Future<void> setNickname(String v) async {
    final p = await _instance();
    await p.setString(_kNickname, v);
  }

  static Future<String> contactPhone() async {
    final p = await _instance();
    return p.getString(_kContactPhone) ?? '';
  }

  static Future<void> setContactPhone(String v) async {
    final p = await _instance();
    await p.setString(_kContactPhone, v);
  }

  static Future<String> email() async {
    final p = await _instance();
    return p.getString(_kEmail) ?? '';
  }

  static Future<void> setEmail(String v) async {
    final p = await _instance();
    await p.setString(_kEmail, v);
  }

  static Future<String> caredName() async {
    final p = await _instance();
    return p.getString(_kCaredName) ?? '';
  }

  static Future<void> setCaredName(String v) async {
    final p = await _instance();
    await p.setString(_kCaredName, v);
  }

  static Future<String> caredAddress() async {
    final p = await _instance();
    return p.getString(_kCaredAddress) ?? '';
  }

  static Future<void> setCaredAddress(String v) async {
    final p = await _instance();
    await p.setString(_kCaredAddress, v);
  }

  // 회원 탈퇴 시 모든 로컬 프로필 값 삭제
  static Future<void> clearProfile() async {
    final p = await _instance();
    await p.remove(_kNickname);
    await p.remove(_kContactPhone);
    await p.remove(_kEmail);
    await p.remove(_kCaredName);
    await p.remove(_kCaredAddress);
  }
}
