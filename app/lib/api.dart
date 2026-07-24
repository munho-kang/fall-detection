// Django API 호출과 토큰 보관

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class UnauthorizedException implements Exception {}

class Api {
  static const _tokenKey = 'fall_token';

  // 우선순위: --dart-define=API_HOST(같은 와이파이의 Mac IP) > 시뮬레이터 기본값.
  // iOS 시뮬레이터·데스크톱은 호스트를 127.0.0.1로 본다.
  // 실기기는 같은 LAN의 Mac IP가 필요하므로 API_HOST로 지정한다.
  static String get baseUrl {
    const host = String.fromEnvironment('API_HOST');
    if (host.isNotEmpty) return 'http://$host:8000';
    return 'http://127.0.0.1:8000';
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

  Future<String> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw Exception('아이디 또는 비밀번호가 올바르지 않습니다.');
    }
    final token = jsonDecode(utf8.decode(res.bodyBytes))['token'] as String;
    await saveToken(token);
    return token;
  }

  Future<String> signup(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/signup/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
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
    final res = await http.get(Uri.parse('$baseUrl/api/falls/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('목록을 불러오지 못했습니다 (${res.statusCode}).');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => FallEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FallEvent> acknowledge(int id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/falls/$id/acknowledge/'),
      headers: _headers,
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('확인 처리에 실패했습니다 (${res.statusCode}).');
    return FallEvent.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<Room>> listRooms() async {
    final res = await http.get(Uri.parse('$baseUrl/api/rooms/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('방 목록을 불러오지 못했습니다 (${res.statusCode}).');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Room> createRoom(String name, int number) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/'),
      headers: _headers,
      body: jsonEncode({'name': name, 'number': number}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 201) {
      throw Exception(_firstErrorMessage(res) ?? '방을 추가하지 못했습니다.');
    }
    return Room.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Room> renameRoom(int id, String name, int number) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/rooms/$id/'),
      headers: _headers,
      body: jsonEncode({'name': name, 'number': number}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) {
      throw Exception(_firstErrorMessage(res) ?? '방 정보를 바꾸지 못했습니다.');
    }
    return Room.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteRoom(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/rooms/$id/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 204) throw Exception('방을 삭제하지 못했습니다 (${res.statusCode}).');
  }

  Future<Profile> getProfile() async {
    final res = await http.get(Uri.parse('$baseUrl/api/profile/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('프로필을 불러오지 못했습니다 (${res.statusCode}).');
    return Profile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Profile> updateProfile(String elderPhone) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/profile/'),
      headers: _headers,
      body: jsonEncode({'elder_phone': elderPhone}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) {
      throw Exception(_firstErrorMessage(res) ?? '전화번호를 저장하지 못했습니다.');
    }
    return Profile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
