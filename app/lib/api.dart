// Django API 호출과 토큰 보관

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class UnauthorizedException implements Exception {}

class Api {
  // 테스트에서 가짜 클라이언트를 꽂을 수 있어야 응답 없는 서버를 재현할 수 있다
  Api({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _tokenKey = 'fall_token';

  // LAN 안의 서버라 정상 응답은 금방 온다. 응답 없는 요청 하나가 화면과 폴러의
  // _inFlight 가드를 무기한 잡아두지 않도록 모든 호출은 5초에 끊는다.
  static const _timeout = Duration(seconds: 5);

  // 우선순위: --dart-define=API_HOST(같은 와이파이의 서버 IP) > 플랫폼 기본값.
  // 웹은 페이지를 서빙한 호스트가 곧 백엔드가 있는 LAN 호스트다(호스트가 없는
  // file:// 실행은 127.0.0.1). iOS 시뮬레이터·데스크톱은 호스트를 127.0.0.1로 본다.
  // Android 에뮬레이터에서 127.0.0.1은 호스트가 아니라 에뮬레이터 자신이다. 호스트는 10.0.2.2다.
  static String get baseUrl => resolveBaseUrl(
        apiHostDefine: const String.fromEnvironment('API_HOST'),
        isWeb: kIsWeb,
        pageUri: Uri.base,
        platform: defaultTargetPlatform,
      );

  // 분기가 전부 파라미터라 VM 테스트에서 웹·Android 경로를 그대로 재현할 수 있다
  @visibleForTesting
  static String resolveBaseUrl({
    required String apiHostDefine,
    required bool isWeb,
    required Uri pageUri,
    required TargetPlatform platform,
  }) {
    if (apiHostDefine.isNotEmpty) return 'http://$apiHostDefine:8000';
    if (isWeb) {
      return pageUri.host.isEmpty
          ? 'http://127.0.0.1:8000'
          : 'http://${pageUri.host}:8000';
    }
    return platform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  String? _token;

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    return _token;
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Token $_token',
      };

  // 모든 HTTP 호출은 이 헬퍼를 거친다 — 타임아웃이 빠진 호출이 생기지 않게 한다.
  // 화면이 예외 문구를 그대로 보여주므로 영어 TimeoutException 대신 한국어로 바꾼다.
  Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(_timeout);
    } on TimeoutException {
      throw Exception('서버가 응답하지 않습니다. 같은 와이파이에 있는지 확인해 주세요.');
    }
  }

  Future<String> login(String username, String password) async {
    final res = await _send(_client.post(
      Uri.parse('$baseUrl/api/auth/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ));
    if (res.statusCode != 200) {
      throw Exception('아이디 또는 비밀번호가 올바르지 않습니다.');
    }
    final token = jsonDecode(utf8.decode(res.bodyBytes))['token'] as String;
    await saveToken(token);
    return token;
  }

  Future<String> signup(String username, String password) async {
    final res = await _send(_client.post(
      Uri.parse('$baseUrl/api/auth/signup/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ));
    if (res.statusCode != 201) {
      throw Exception(_firstErrorMessage(res) ?? '회원가입에 실패했습니다.');
    }
    final token = jsonDecode(utf8.decode(res.bodyBytes))['token'] as String;
    await saveToken(token); // 가입 즉시 발급된 토큰 — 별도 로그인이 필요 없다
    return token;
  }

  // DRF 검증 에러({필드: [메시지, ...]})의 첫 메시지를 꺼낸다. 서버가 한국어로 내려준다.
  String? _firstErrorMessage(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map<String, dynamic> && body.isNotEmpty) {
        final first = body.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first is String) return first;
      }
    } catch (_) {
      // 본문이 JSON이 아니면 기본 문구를 쓴다
    }
    return null;
  }

  Future<List<FallEvent>> listFalls() async {
    final res = await _send(_client.get(Uri.parse('$baseUrl/api/falls/'), headers: _headers));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('목록을 불러오지 못했습니다 (${res.statusCode}).');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => FallEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FallEvent> acknowledge(int id) async {
    final res = await _send(_client.post(
      Uri.parse('$baseUrl/api/falls/$id/acknowledge/'),
      headers: _headers,
    ));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('확인 처리에 실패했습니다 (${res.statusCode}).');
    return FallEvent.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteFall(int id) async {
    final res = await _send(_client.delete(Uri.parse('$baseUrl/api/falls/$id/'), headers: _headers));
    if (res.statusCode == 401) throw UnauthorizedException();
    // 미확인 기록 삭제는 서버가 400 + 한국어 문구로 거절한다. 문구를 새로 짓지 말고 그대로 올린다.
    if (res.statusCode != 204) {
      throw Exception(_firstErrorMessage(res) ?? '기록을 삭제하지 못했습니다 (${res.statusCode}).');
    }
  }

  Future<List<Room>> listRooms() async {
    final res = await _send(_client.get(Uri.parse('$baseUrl/api/rooms/'), headers: _headers));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('방 목록을 불러오지 못했습니다 (${res.statusCode}).');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Room> createRoom(String name, int number) async {
    final res = await _send(_client.post(
      Uri.parse('$baseUrl/api/rooms/'),
      headers: _headers,
      body: jsonEncode({'name': name, 'number': number}),
    ));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 201) {
      throw Exception(_firstErrorMessage(res) ?? '방을 추가하지 못했습니다.');
    }
    return Room.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Room> renameRoom(int id, String name, int number) async {
    final res = await _send(_client.patch(
      Uri.parse('$baseUrl/api/rooms/$id/'),
      headers: _headers,
      body: jsonEncode({'name': name, 'number': number}),
    ));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) {
      throw Exception(_firstErrorMessage(res) ?? '방 정보를 바꾸지 못했습니다.');
    }
    return Room.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteRoom(int id) async {
    final res = await _send(_client.delete(Uri.parse('$baseUrl/api/rooms/$id/'), headers: _headers));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 204) throw Exception('방을 삭제하지 못했습니다 (${res.statusCode}).');
  }

  Future<Profile> getProfile() async {
    final res = await _send(_client.get(Uri.parse('$baseUrl/api/profile/'), headers: _headers));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('프로필을 불러오지 못했습니다 (${res.statusCode}).');
    return Profile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Profile> updateProfile(String elderPhone) async {
    final res = await _send(_client.put(
      Uri.parse('$baseUrl/api/profile/'),
      headers: _headers,
      body: jsonEncode({'elder_phone': elderPhone}),
    ));
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) {
      throw Exception(_firstErrorMessage(res) ?? '전화번호를 저장하지 못했습니다.');
    }
    return Profile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
