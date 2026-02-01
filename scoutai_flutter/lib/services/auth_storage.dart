import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _tokenKey = 'scoutai_token_v1';
  static String? _sessionToken;

  static Future<void> saveToken(String token, {bool remember = true}) async {
    _sessionToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (remember) {
      await prefs.setString(_tokenKey, token);
    } else {
      await prefs.remove(_tokenKey);
    }
  }

  static Future<String?> loadToken() async {
    final session = _sessionToken;
    if (session != null && session.isNotEmpty) return session;
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey);
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static Future<void> clear() async {
    _sessionToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}
