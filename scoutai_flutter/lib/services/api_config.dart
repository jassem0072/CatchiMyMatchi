import 'package:flutter/foundation.dart';

class ApiConfig {
  static const _override = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get baseUrl {
    // 1) dart-define override (production / Render URL)
    if (_override.isNotEmpty) return _override;
    // 2) Web
    if (kIsWeb) return 'http://localhost:3000';
    // 3) Android emulator
    if (defaultTargetPlatform == TargetPlatform.android &&
        !kIsWeb &&
        const bool.fromEnvironment('dart.vm.product')) {
      // Real device: use your computer's LAN IP
      // Find it with: ipconfig (Windows) → look for IPv4 under Wi-Fi/Ethernet
      return 'http://192.168.100.9:3000';
    }
    // 4) Android emulator (debug)
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:3000';
    // 5) Desktop / other
    return 'http://localhost:3000';
  }
}
