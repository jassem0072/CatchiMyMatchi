import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class AuthApi {
  AuthApi({String? baseUrl}) : baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/$'), '');

  final String baseUrl;

  Future<String> signup({
    required String email,
    required String password,
    required String role,
    String? displayName,
    String? position,
    String? nation,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/signup');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'role': role,
        if (displayName != null && displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
        if (position != null && position.trim().isNotEmpty) 'position': position.trim(),
        if (nation != null && nation.trim().isNotEmpty) 'nation': nation.trim(),
      }),
    );

    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Sign up failed');
    final token = data['accessToken'];
    if (token is! String || token.isEmpty) throw Exception('Missing accessToken');
    return token;
  }

  Future<String> google({String? idToken, String? accessToken, String? role}) async {
    final id = idToken?.trim();
    final at = accessToken?.trim();
    if ((id == null || id.isEmpty) && (at == null || at.isEmpty)) {
      throw Exception('Missing Google token');
    }

    final uri = Uri.parse('$baseUrl/auth/google');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (id != null && id.isNotEmpty) 'idToken': id,
        if (at != null && at.isNotEmpty) 'accessToken': at,
        if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
      }),
    );

    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Google sign in failed');
    final token = data['accessToken'];
    if (token is! String || token.isEmpty) throw Exception('Missing accessToken');
    return token;
  }

  Future<String> signin({required String email, required String password}) async {
    final uri = Uri.parse('$baseUrl/auth/signin');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Sign in failed');
    final token = data['accessToken'];
    if (token is! String || token.isEmpty) throw Exception('Missing accessToken');
    return token;
  }

  Future<Map<String, dynamic>> me(String token) async {
    final uri = Uri.parse('$baseUrl/auth/me');
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Failed to load profile');
    return data;
  }

  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final uri = Uri.parse('$baseUrl/auth/forgot-password');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Forgot password failed');
    return data;
  }

  Future<void> resetPassword({required String email, required String token, required String newPassword}) async {
    final uri = Uri.parse('$baseUrl/auth/reset-password');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'token': token, 'newPassword': newPassword}),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Reset password failed');
  }

  Map<String, dynamic> _decodeJson(http.Response res) {
    try {
      final parsed = jsonDecode(res.body);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'data': parsed};
    } catch (_) {
      return {'message': res.body};
    }
  }

  String? _errorMessage(Map<String, dynamic> data) {
    final msg = data['message'];
    if (msg is String) return msg;
    if (msg is List && msg.isNotEmpty) return msg.first.toString();
    final err = data['error'];
    if (err is String) return err;
    return null;
  }
}
