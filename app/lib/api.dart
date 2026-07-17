// Django API 호출과 토큰 보관

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class UnauthorizedException implements Exception {}

class Api {
  static const _tokenKey = 'fall_token';

  // Android 에뮬레이터는 호스트를 10.0.2.2로 본다. iOS 시뮬레이터와 데스크톱은
  // 호스트 네트워크를 그대로 공유하므로 127.0.0.1이다.
  static String get baseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';

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
}
