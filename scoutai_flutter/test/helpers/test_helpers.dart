import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets up mock SharedPreferences with a valid auth token for service tests.
void setupMockSharedPreferences() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, dynamic>{
          'flutter.scoutai_token_v1': 'mock-token-123',
        };
      }
      return null;
    },
  );
}

/// Tears down mock SharedPreferences.
void tearDownMockSharedPreferences() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    null,
  );
}
