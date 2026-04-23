import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/player/models/player_video_dto.dart';

void main() {
  group('PlayerVideoDto.fromJson', () {
    test('parses complete JSON with lastAnalysis', () {
      final json = <String, dynamic>{
        '_id': 'v1',
        'originalName': 'match_video.mp4',
        'createdAt': '2025-06-15T10:30:00Z',
        'lastAnalysis': <String, dynamic>{
          'distanceKm': 10.5,
          'maxSpeedKmh': 33.2,
          'sprints': 22,
        },
      };

      final dto = PlayerVideoDto.fromJson(json);
      expect(dto.id, 'v1');
      expect(dto.originalName, 'match_video.mp4');
      expect(dto.createdAt, isNotNull);
      expect(dto.lastAnalysis, isNotNull);
      expect(dto.lastAnalysis!.distanceKm, 10.5);
      expect(dto.lastAnalysis!.maxSpeedKmh, 33.2);
      expect(dto.lastAnalysis!.sprints, 22);
    });

    test('parses JSON without lastAnalysis', () {
      final json = <String, dynamic>{
        'id': 'v2',
        'originalName': 'training.mp4',
      };

      final dto = PlayerVideoDto.fromJson(json);
      expect(dto.id, 'v2');
      expect(dto.originalName, 'training.mp4');
      expect(dto.lastAnalysis, isNull);
    });

    test('uses "filename" fallback for originalName', () {
      final json = <String, dynamic>{
        'id': 'v3',
        'filename': 'clip.mp4',
      };

      final dto = PlayerVideoDto.fromJson(json);
      expect(dto.originalName, 'clip.mp4');
    });

    test('defaults to "Video" when no name fields present', () {
      final dto = PlayerVideoDto.fromJson(const <String, dynamic>{});
      expect(dto.originalName, 'Video');
      expect(dto.id, '');
    });

    test('returns null createdAt for invalid date string', () {
      final json = <String, dynamic>{
        'createdAt': 'not-a-date',
      };

      final dto = PlayerVideoDto.fromJson(json);
      expect(dto.createdAt, isNull);
    });
  });

  group('PlayerVideoAnalysisDto.fromJson', () {
    test('reads metrics from nested metrics object', () {
      final json = <String, dynamic>{
        'metrics': <String, dynamic>{
          'distanceKm': 9.8,
          'maxSpeedKmh': 30.0,
          'sprints': 15,
        },
      };

      final dto = PlayerVideoAnalysisDto.fromJson(json);
      expect(dto.distanceKm, 9.8);
      expect(dto.maxSpeedKmh, 30.0);
      expect(dto.sprints, 15);
    });

    test('reads metrics from flat fields over nested', () {
      final json = <String, dynamic>{
        'distanceKm': 8.0,
        'maxSpeedKmh': 28.0,
        'sprints': 10,
        'metrics': <String, dynamic>{
          'distanceKm': 999.0,
        },
      };

      final dto = PlayerVideoAnalysisDto.fromJson(json);
      expect(dto.distanceKm, 8.0); // flat takes priority
    });

    test('handles alternative field names', () {
      final json = <String, dynamic>{
        'distance_km': 7.5,
        'max_speed_kmh': 25.0,
        'sprintCount': 8,
      };

      final dto = PlayerVideoAnalysisDto.fromJson(json);
      expect(dto.distanceKm, 7.5);
      expect(dto.maxSpeedKmh, 25.0);
      expect(dto.sprints, 8);
    });

    test('handles string numeric values', () {
      final json = <String, dynamic>{
        'distanceKm': '11.2',
        'maxSpeedKmh': '35',
        'sprints': '20',
      };

      final dto = PlayerVideoAnalysisDto.fromJson(json);
      expect(dto.distanceKm, 11.2);
      expect(dto.maxSpeedKmh, 35.0);
      expect(dto.sprints, 20);
    });

    test('defaults to zero for missing values', () {
      final dto = PlayerVideoAnalysisDto.fromJson(const <String, dynamic>{});
      expect(dto.distanceKm, 0.0);
      expect(dto.maxSpeedKmh, 0.0);
      expect(dto.sprints, 0);
    });
  });
}
