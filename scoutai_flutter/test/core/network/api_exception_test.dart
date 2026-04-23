import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/core/network/api_exception.dart';

void main() {
  group('ApiException', () {
    test('toString returns message when statusCode is null', () {
      final exception = ApiException('Something went wrong');
      expect(exception.toString(), 'Something went wrong');
    });

    test('toString includes status code when present', () {
      final exception = ApiException('Not found', statusCode: 404);
      expect(exception.toString(), 'API 404: Not found');
    });

    test('message and statusCode are stored correctly', () {
      final exception = ApiException('Unauthorized', statusCode: 401);
      expect(exception.message, 'Unauthorized');
      expect(exception.statusCode, 401);
    });

    test('implements Exception', () {
      final exception = ApiException('Error');
      expect(exception, isA<Exception>());
    });
  });
}
