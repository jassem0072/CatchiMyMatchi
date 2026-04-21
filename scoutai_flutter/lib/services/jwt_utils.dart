import 'dart:convert';

/// Decode a JWT payload without verifying the signature.
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return {};
  String payload = parts[1];
  // Base64 padding
  switch (payload.length % 4) {
    case 2:
      payload += '==';
      break;
    case 3:
      payload += '=';
      break;
  }
  final decoded = utf8.decode(base64Url.decode(payload));
  final map = jsonDecode(decoded);
  return map is Map<String, dynamic> ? map : {};
}

/// Extract the role from a JWT token. Returns 'player' or 'scouter'.
String roleFromToken(String token) {
  final payload = decodeJwtPayload(token);
  final role = payload['role'];
  if (role is String && role.isNotEmpty) return role;
  return 'player';
}
