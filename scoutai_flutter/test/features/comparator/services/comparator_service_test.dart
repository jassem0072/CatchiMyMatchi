import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:scoutai/core/network/api_client.dart';
import 'package:scoutai/features/comparator/services/comparator_service.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const baseUrl = 'https://api.test.com';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setupMockSharedPreferences());
  tearDown(() => tearDownMockSharedPreferences());

  group('ComparatorService.getPlayers', () {
    test('returns list of ComparatorPlayer', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/players') {
          return http.Response(
            jsonEncode([
              {
                '_id': 'p1',
                'displayName': 'Player A',
                'email': 'a@test.com',
                'position': 'ST',
                'nation': 'France',
                'playerIdNumber': 'PID1',
              },
              {
                '_id': 'p2',
                'displayName': 'Player B',
                'email': 'b@test.com',
                'position': 'GK',
                'nation': 'Spain',
                'playerIdNumber': 'PID2',
              },
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ComparatorService(apiClient);
      final players = await service.getPlayers();

      expect(players, hasLength(2));
      expect(players[0].id, 'p1');
      expect(players[0].displayName, 'Player A');
      expect(players[1].id, 'p2');
    });

    test('returns empty list for non-list response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode({'error': 'nope'}), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ComparatorService(apiClient);
      final players = await service.getPlayers();

      expect(players, isEmpty);
    });
  });

  group('ComparatorService.comparePlayers', () {
    test('returns ComparatorResult', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/players/compare') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['playerIdA'], 'pA');
          expect(body['playerIdB'], 'pB');
          return http.Response(
            jsonEncode({
              'playerA': {
                'aggregated': {
                  'totalDistanceMeters': 10000.0,
                  'maxSpeedKmh': 32.0,
                  'avgSpeedKmh': 8.0,
                  'totalSprints': 20.0,
                  'totalAccelPeaks': 5.0,
                  'analyzedVideos': 3.0,
                },
                'videos': [],
              },
              'playerB': {
                'aggregated': {
                  'totalDistanceMeters': 9000.0,
                  'maxSpeedKmh': 30.0,
                  'avgSpeedKmh': 7.0,
                  'totalSprints': 15.0,
                  'totalAccelPeaks': 3.0,
                  'analyzedVideos': 2.0,
                },
                'videos': [],
              },
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ComparatorService(apiClient);
      final result = await service.comparePlayers(
        playerIdA: 'pA',
        playerIdB: 'pB',
      );

      expect(result.playerA.aggregated.totalDistanceMeters, 10000.0);
      expect(result.playerB.aggregated.totalDistanceMeters, 9000.0);
    });

    test('throws on non-map response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode([1, 2]), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ComparatorService(apiClient);

      expect(
        () => service.comparePlayers(playerIdA: 'a', playerIdB: 'b'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ComparatorService.getPlayerPortrait', () {
    test('returns bytes for valid image', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47],
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ComparatorService(apiClient);
      final bytes = await service.getPlayerPortrait('p1');

      expect(bytes, isNotNull);
      expect(bytes, hasLength(4));
    });

    test('returns null for empty playerId', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('', 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ComparatorService(apiClient);
      final bytes = await service.getPlayerPortrait('');

      expect(bytes, isNull);
    });

    test('returns null for non-image content-type', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response.bytes(
          [0x00, 0x01],
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ComparatorService(apiClient);
      final bytes = await service.getPlayerPortrait('p1');

      expect(bytes, isNull);
    });
  });
}
