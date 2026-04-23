import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:scoutai/core/network/api_client.dart';
import 'package:scoutai/core/network/api_exception.dart';

void main() {
  const testBaseUrl = 'https://api.test.com';

  ApiClient createClient(http_testing.MockClient mockClient) {
    return ApiClient(client: mockClient, baseUrl: testBaseUrl);
  }

  group('ApiClient.get', () {
    test('returns decoded JSON on success', () async {
      final mock = http_testing.MockClient((request) async {
        expect(request.url.toString(), startsWith(testBaseUrl));
        return http.Response(
          jsonEncode({'name': 'Test'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = createClient(mock);
      final result = await client.get('/test', authenticated: false);
      expect(result, isA<Map<String, dynamic>>());
      expect(result['name'], 'Test');
    });

    test('includes query parameters', () async {
      final mock = http_testing.MockClient((request) async {
        expect(request.url.queryParameters['foo'], 'bar');
        return http.Response('{}', 200);
      });

      final client = createClient(mock);
      await client.get('/test', authenticated: false, query: {'foo': 'bar'});
    });

    test('throws ApiException on 404', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Not found'}),
          404,
        );
      });

      final client = createClient(mock);
      expect(
        () => client.get('/missing', authenticated: false),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException with string body on error', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('Server error text', 500);
      });

      final client = createClient(mock);
      try {
        await client.get('/fail', authenticated: false);
        fail('Should have thrown');
      } on ApiException catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, 'Server error text');
      }
    });

    test('throws ApiException on empty body error', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('', 500, reasonPhrase: 'Internal Server Error');
      });

      final client = createClient(mock);
      try {
        await client.get('/fail', authenticated: false);
        fail('Should have thrown');
      } on ApiException catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, 'Internal Server Error');
      }
    });
  });

  group('ApiClient.post', () {
    test('sends JSON body and returns response', () async {
      final mock = http_testing.MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['key'], 'value');
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      final client = createClient(mock);
      final result = await client.post(
        '/submit',
        authenticated: false,
        body: {'key': 'value'},
      );
      expect(result['ok'], true);
    });

    test('handles null body', () async {
      final mock = http_testing.MockClient((request) async {
        expect(request.body, isEmpty);
        return http.Response('{}', 200);
      });

      final client = createClient(mock);
      await client.post('/submit', authenticated: false);
    });

    test('throws ApiException on error response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Bad request'}),
          400,
        );
      });

      final client = createClient(mock);
      expect(
        () => client.post('/submit', authenticated: false),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ApiClient.patch', () {
    test('sends PATCH request with body', () async {
      final mock = http_testing.MockClient((request) async {
        expect(request.method, 'PATCH');
        return http.Response(jsonEncode({'updated': true}), 200);
      });

      final client = createClient(mock);
      final result = await client.patch(
        '/update',
        authenticated: false,
        body: {'field': 'new_value'},
      );
      expect(result['updated'], true);
    });
  });

  group('ApiClient.getBytes', () {
    test('returns raw response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47], // PNG magic bytes
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final client = createClient(mock);
      final response = await client.getBytes('/image', authenticated: false);
      expect(response.bodyBytes, hasLength(4));
      expect(response.headers['content-type'], 'image/png');
    });

    test('throws on error status', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('Not found', 404);
      });

      final client = createClient(mock);
      expect(
        () => client.getBytes('/missing', authenticated: false),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ApiClient._decode', () {
    test('returns null for empty body', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('', 200);
      });

      final client = createClient(mock);
      final result = await client.get('/empty', authenticated: false);
      expect(result, isNull);
    });

    test('returns string for non-JSON body', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('just plain text', 200);
      });

      final client = createClient(mock);
      final result = await client.get('/text', authenticated: false);
      expect(result, 'just plain text');
    });

    test('returns list for JSON array', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('[1, 2, 3]', 200);
      });

      final client = createClient(mock);
      final result = await client.get('/list', authenticated: false);
      expect(result, [1, 2, 3]);
    });
  });
}
