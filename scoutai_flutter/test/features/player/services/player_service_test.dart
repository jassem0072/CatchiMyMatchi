import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:scoutai/core/network/api_client.dart';
import 'package:scoutai/features/player/services/player_service.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const baseUrl = 'https://api.test.com';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setupMockSharedPreferences());
  tearDown(() => tearDownMockSharedPreferences());

  group('PlayerService.getCurrentPlayer', () {
    test('returns a Player from /me endpoint', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/me') {
          return http.Response(
            jsonEncode({
              '_id': 'player1',
              'displayName': 'John Doe',
              'email': 'john@test.com',
              'position': 'st',
              'nation': 'England',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = PlayerService(apiClient);
      final player = await service.getCurrentPlayer();

      expect(player.id, 'player1');
      expect(player.displayName, 'John Doe');
      expect(player.position, 'ST');
    });

    test('throws on non-map response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode([1, 2, 3]), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = PlayerService(apiClient);

      expect(
        () => service.getCurrentPlayer(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PlayerService.getCurrentPlayerVideos', () {
    test('returns list of PlayerVideo from /me/videos', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/me/videos') {
          return http.Response(
            jsonEncode([
              {
                '_id': 'v1',
                'originalName': 'match.mp4',
                'createdAt': '2025-01-01T00:00:00Z',
              },
              {
                '_id': 'v2',
                'originalName': 'training.mp4',
              },
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = PlayerService(apiClient);
      final videos = await service.getCurrentPlayerVideos();

      expect(videos, hasLength(2));
      expect(videos[0].id, 'v1');
      expect(videos[0].originalName, 'match.mp4');
      expect(videos[1].id, 'v2');
    });

    test('throws on non-list response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode({'error': 'nope'}), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = PlayerService(apiClient);

      expect(
        () => service.getCurrentPlayerVideos(),
        throwsA(isA<Exception>()),
      );
    });

    test('falls back to /videos on 403', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/me/videos') {
          return http.Response(jsonEncode({'message': 'Forbidden'}), 403);
        }
        if (request.url.path == '/videos') {
          return http.Response(
            jsonEncode([
              {'_id': 'v1', 'originalName': 'fallback.mp4'},
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = PlayerService(apiClient);
      final videos = await service.getCurrentPlayerVideos();

      expect(videos, hasLength(1));
      expect(videos[0].originalName, 'fallback.mp4');
    });
  });
}
