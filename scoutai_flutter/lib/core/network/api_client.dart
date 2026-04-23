import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/api_config.dart';
import '../../services/auth_storage.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalized').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({bool authenticated = true}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (!authenticated) return headers;
    final token = await AuthStorage.loadToken();
    if (token == null || token.isEmpty) {
      throw ApiException('Missing authentication token', statusCode: 401);
    }
    headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return response.body;
    }
  }

  Never _throwError(http.Response response, dynamic data) {
    final fallback = response.reasonPhrase?.trim();
    if (data is Map<String, dynamic>) {
      final message = (data['message'] ?? data['error'] ?? fallback ?? 'Request failed').toString();
      throw ApiException(message, statusCode: response.statusCode);
    }
    if (data is String && data.trim().isNotEmpty) {
      throw ApiException(data.trim(), statusCode: response.statusCode);
    }
    throw ApiException(fallback?.isNotEmpty == true ? fallback! : 'Request failed', statusCode: response.statusCode);
  }

  Future<dynamic> get(
    String path, {
    bool authenticated = true,
    Map<String, String>? query,
  }) async {
    final response = await _client.get(
      _uri(path, query),
      headers: await _headers(authenticated: authenticated),
    );
    final data = _decode(response);
    if (response.statusCode >= 400) _throwError(response, data);
    return data;
  }

  Future<dynamic> post(
    String path, {
    bool authenticated = true,
    Object? body,
  }) async {
    final response = await _client.post(
      _uri(path),
      headers: await _headers(authenticated: authenticated),
      body: body == null ? null : jsonEncode(body),
    );
    final data = _decode(response);
    if (response.statusCode >= 400) _throwError(response, data);
    return data;
  }

  Future<dynamic> patch(
    String path, {
    bool authenticated = true,
    Object? body,
  }) async {
    final response = await _client.patch(
      _uri(path),
      headers: await _headers(authenticated: authenticated),
      body: body == null ? null : jsonEncode(body),
    );
    final data = _decode(response);
    if (response.statusCode >= 400) _throwError(response, data);
    return data;
  }

  Future<http.Response> getBytes(
    String path, {
    bool authenticated = true,
    Map<String, String>? query,
  }) async {
    final response = await _client.get(
      _uri(path, query),
      headers: await _headers(authenticated: authenticated),
    );
    if (response.statusCode >= 400) {
      final data = _decode(response);
      _throwError(response, data);
    }
    return response;
  }
}
