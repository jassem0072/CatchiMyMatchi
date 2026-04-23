import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:scoutai/core/network/api_client.dart';
import 'package:scoutai/features/profile/services/profile_service.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const baseUrl = 'https://api.test.com';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setupMockSharedPreferences());
  tearDown(() => tearDownMockSharedPreferences());

  group('ProfileService.loadProfileSummary', () {
    test('returns ProfileSummary with player, portrait, videos', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/me' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              '_id': 'p1',
              'displayName': 'Test Player',
              'email': 'test@test.com',
              'position': 'ST',
              'nation': 'France',
            }),
            200,
          );
        }
        if (request.url.path == '/me/portrait') {
          return http.Response.bytes(
            [0x89, 0x50, 0x4E, 0x47],
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        if (request.url.path == '/me/videos') {
          return http.Response(
            jsonEncode([
              {'_id': 'v1', 'originalName': 'video.mp4'},
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ProfileService(apiClient);
      final summary = await service.loadProfileSummary();

      expect(summary.player.id, 'p1');
      expect(summary.player.displayName, 'Test Player');
      expect(summary.portraitBytes, isNotNull);
      expect(summary.portraitBytes, hasLength(4));
      expect(summary.videos, hasLength(1));
    });

    test('returns null portrait for non-image content', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/me') {
          return http.Response(jsonEncode({
            '_id': 'p1', 'displayName': 'X', 'email': 'x@x.com',
            'position': 'GK', 'nation': '',
          }), 200);
        }
        if (request.url.path == '/me/portrait') {
          return http.Response.bytes(
            [0x00], 200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/me/videos') {
          return http.Response('[]', 200);
        }
        return http.Response('', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ProfileService(apiClient);
      final summary = await service.loadProfileSummary();

      expect(summary.portraitBytes, isNull);
    });

    test('throws on invalid /me response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode([1, 2]), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ProfileService(apiClient);

      expect(
        () => service.loadProfileSummary(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ProfileService.getCurrentPlayer', () {
    test('returns Player from /me', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({
            '_id': 'p1', 'displayName': 'Jane',
            'email': 'jane@test.com', 'position': 'CB', 'nation': 'Spain',
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ProfileService(apiClient);
      final player = await service.getCurrentPlayer();

      expect(player.displayName, 'Jane');
      expect(player.position, 'CB');
    });
  });
}
