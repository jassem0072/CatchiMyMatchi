import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:scoutai/core/network/api_client.dart';
import 'package:scoutai/features/analysis/models/analysis_run_request.dart';
import 'package:scoutai/features/analysis/models/analysis_selection.dart';
import 'package:scoutai/features/analysis/services/analysis_run_service.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const baseUrl = 'https://api.test.com';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setupMockSharedPreferences());
  tearDown(() => tearDownMockSharedPreferences());

  group('AnalysisRunService.runAnalysis', () {
    test('posts analysis request and returns result', () async {
      final mock = http_testing.MockClient((request) async {
        expect(request.url.path, '/videos/vid1/analyze');
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['samplingFps'], 4);
        expect(body['selection'], isA<Map>());

        return http.Response(
          jsonEncode({'status': 'started', 'analysisId': 'a1'}),
          200,
        );
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = AnalysisRunService(apiClient);

      const request = AnalysisRunRequest(
        videoId: 'vid1',
        selection: AnalysisSelection(t0: 0, x: 10, y: 20, w: 100, h: 80),
      );

      final result = await service.runAnalysis(request);
      expect(result.raw['status'], 'started');
      expect(result.raw['analysisId'], 'a1');
    });

    test('throws on empty videoId', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response('{}', 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = AnalysisRunService(apiClient);

      const request = AnalysisRunRequest(
        videoId: '  ',
        selection: AnalysisSelection(t0: 0, x: 0, y: 0, w: 0, h: 0),
      );

      expect(
        () => service.runAnalysis(request),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on non-map response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode([1, 2, 3]), 200);
      });

      final apiClient = ApiClient(client: mock, baseUrl: baseUrl);
      final service = AnalysisRunService(apiClient);

      const request = AnalysisRunRequest(
        videoId: 'vid1',
        selection: AnalysisSelection(t0: 0, x: 0, y: 0, w: 0, h: 0),
      );

      expect(
        () => service.runAnalysis(request),
        throwsA(isA<Exception>()),
      );
    });
  });
}
