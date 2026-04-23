import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:scoutai/core/network/api_client.dart';
import 'package:scoutai/features/scouter/services/scouter_service.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const baseUrl = 'https://api.test.com';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setupMockSharedPreferences());
  tearDown(() => tearDownMockSharedPreferences());

  // Full workflow JSON matching all required fields in ScouterPlayerWorkflowDto
  Map<String, dynamic> workflowJson({String verificationStatus = 'not_requested'}) {
    return {
      'verificationStatus': verificationStatus,
      'preContractStatus': 'none',
      'scouterPlatformFeePaid': false,
      'scouterSignedContract': false,
      'contractSignedByPlayer': false,
      'fixedPrice': 0,
      'contractSignedAt': '',
      'scouterSignedAt': '',
      'playerSignatureImageBase64': '',
      'playerSignatureImageContentType': '',
      'playerSignatureImageFileName': '',
      'scouterSignatureImageBase64': '',
      'scouterSignatureImageContentType': '',
      'scouterSignatureImageFileName': '',
    };
  }

  group('ScouterService.getCurrentScouter', () {
    test('returns a Scouter from /me', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/me') {
          return http.Response(
            jsonEncode({
              '_id': 's1',
              'displayName': 'Scout Master',
              'email': 'scout@test.com',
              'role': 'scouter',
              'nation': 'France',
              'tier': 'premium',
              'verified': true,
              'isPremium': true,
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);
      final scouter = await service.getCurrentScouter();

      expect(scouter.id, 's1');
      expect(scouter.displayName, 'Scout Master');
      expect(scouter.isPremium, true);
    });

    test('throws on non-map response', () {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode([1]), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);

      expect(
        () => service.getCurrentScouter(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ScouterService.getFavoritePlayers', () {
    test('returns only favorite players', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/players') {
          return http.Response(
            jsonEncode([
              {
                '_id': 'p1',
                'displayName': 'Favorite',
                'email': 'f@t.com',
                'position': 'ST',
                'nation': 'France',
                'playerIdNumber': 'PID1',
                'isFavorite': true,
              },
              {
                '_id': 'p2',
                'displayName': 'Not Favorite',
                'email': 'nf@t.com',
                'position': 'GK',
                'nation': 'Spain',
                'playerIdNumber': 'PID2',
                'isFavorite': false,
              },
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);
      final favorites = await service.getFavoritePlayers();

      expect(favorites, hasLength(1));
      expect(favorites[0].displayName, 'Favorite');
      expect(favorites[0].isFavorite, true);
    });

    test('returns empty for non-list response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode({'error': 'nope'}), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);
      final result = await service.getFavoritePlayers();

      expect(result, isEmpty);
    });
  });

  group('ScouterService.getScouterPlayerWorkflow', () {
    test('returns null for empty playerId', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('{}', 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);
      final result = await service.getScouterPlayerWorkflow('  ');

      expect(result, isNull);
    });

    test('returns workflow from admin endpoint', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/admin/players/p1') {
          return http.Response(
            jsonEncode({
              'workflow': workflowJson(verificationStatus: 'identified'),
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);
      final workflow = await service.getScouterPlayerWorkflow('p1');

      expect(workflow, isNotNull);
      expect(workflow!.verificationStatus, 'identified');
    });

    test('falls back to dashboard endpoint when admin throws', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/admin/players/p1') {
          // Throw so _tryFetchAdminWorkflow catches and returns null
          return http.Response(
            jsonEncode({'message': 'Forbidden'}),
            403,
          );
        }
        if (request.url.path == '/players/p1/dashboard') {
          return http.Response(
            jsonEncode({
              'player': {
                'adminWorkflow':
                    workflowJson(verificationStatus: 'contacted'),
              },
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);
      final workflow = await service.getScouterPlayerWorkflow('p1');

      expect(workflow, isNotNull);
      expect(workflow!.verificationStatus, 'contacted');
    });

    test('returns null when both endpoints fail', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('Error', 500);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = ScouterService(apiClient);
      final workflow = await service.getScouterPlayerWorkflow('p1');

      expect(workflow, isNull);
    });
  });
}
