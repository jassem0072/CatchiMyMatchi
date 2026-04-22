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
    // Current backend returns { email } for signup, not a JWT token.
    final returnedEmail = data['email'];
    if (returnedEmail is String && returnedEmail.trim().isNotEmpty) {
      return returnedEmail.trim();
    }

    // Backward-compatible fallback if an older backend returns accessToken.
    final token = data['accessToken'];
    if (token is String && token.isNotEmpty) {
      return email.trim();
    }

    throw Exception('Unexpected signup response');
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

  /// Create a Stripe Checkout Session for scouter upgrade.
  /// Returns { checkoutUrl, sessionId }.
  Future<Map<String, dynamic>> createCheckoutSession(String currentToken, {String? returnUrl}) async {
    final uri = Uri.parse('$baseUrl/me/create-checkout-session');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $currentToken',
      },
      body: jsonEncode({
        if (returnUrl != null) 'returnUrl': returnUrl,
      }),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Failed to create checkout session');
    return data;
  }

  /// Google sign-in for web: uses verified email/displayName instead of tokens.
  Future<String> googleWeb({required String email, required String displayName, String? role}) async {
    final uri = Uri.parse('$baseUrl/auth/google-web');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'displayName': displayName,
        if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
      }),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Google sign in failed');
    final token = data['accessToken'];
    if (token is! String || token.isEmpty) throw Exception('Missing accessToken');
    return token;
  }

  /// Send or resend a 6-digit email verification code.
  Future<void> resendCode({required String email}) async {
    final uri = Uri.parse('$baseUrl/auth/resend-code');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Failed to send code');
  }

  /// Verify the 6-digit email code and return the JWT on success.
  Future<String> verifyCode({required String email, required String code}) async {
    final uri = Uri.parse('$baseUrl/auth/verify-code');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Verification failed');
    final token = data['accessToken'];
    if (token is! String || token.isEmpty) throw Exception('Missing accessToken');
    return token;
  }

  /// Update the current user's profile fields.
  Future<void> updateProfile(
    String currentToken, {
    String? displayName,
    String? position,
    String? nation,
    String? dateOfBirth,
    int? height,
    String? playerIdNumber,
  }) async {
    final uri = Uri.parse('$baseUrl/me');
    final res = await http.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $currentToken',
      },
      body: jsonEncode({
        if (displayName != null) 'displayName': displayName,
        if (position != null) 'position': position,
        if (nation != null) 'nation': nation,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (height != null) 'height': height,
        if (playerIdNumber != null) 'playerIdNumber': playerIdNumber,
      }),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Profile update failed');
  }

  Future<Map<String, dynamic>> payAndUpgrade(
    String currentToken, {
    required String cardNumber,
    required int expMonth,
    required int expYear,
    required String cvc,
    String? tier,
  }) async {
    final uri = Uri.parse('$baseUrl/me/pay-and-upgrade');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $currentToken',
      },
      body: jsonEncode({
        'cardNumber': cardNumber,
        'expMonth': expMonth,
        'expYear': expYear,
        'cvc': cvc,
        if (tier != null && tier.isNotEmpty) 'tier': tier,
      }),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Payment failed');
    return data;
  }

  Future<Map<String, dynamic>> checkUpgradeStatus(String currentToken, String sessionId) async {
    final uri = Uri.parse('$baseUrl/me/upgrade-status?sessionId=${Uri.encodeComponent(sessionId)}');
    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $currentToken',
      },
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) throw Exception(_errorMessage(data) ?? 'Failed to check upgrade status');
    return data;
  }

  Future<Map<String, dynamic>> saveCommunicationQuizResult(
    String currentToken, {
    required String language,
    required int score,
    required int totalQuestions,
    required String readinessBand,
    String? communicationStyle,
    String? captaincySummary,
  }) async {
    final uri = Uri.parse('$baseUrl/me/communication-quiz');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $currentToken',
      },
      body: jsonEncode({
        'language': language,
        'score': score,
        'totalQuestions': totalQuestions,
        'readinessBand': readinessBand,
        if (communicationStyle != null && communicationStyle.isNotEmpty)
          'communicationStyle': communicationStyle,
        if (captaincySummary != null && captaincySummary.isNotEmpty)
          'captaincySummary': captaincySummary,
      }),
    );
    final data = _decodeJson(res);
    if (res.statusCode >= 400) {
      throw Exception(_errorMessage(data) ?? 'Failed to save communication quiz result');
    }
    return data;
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
