import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/comparator/models/comparator_result_dto.dart';

void main() {
  // Helper: minimal aggregated JSON with correct field names
  Map<String, dynamic> aggJson({double distance = 0.0, double maxSpeed = 0.0}) {
    return {
      'totalDistanceMeters': distance,
      'maxSpeedKmh': maxSpeed,
      'avgSpeedKmh': 0.0,
      'totalSprints': 0.0,
      'totalAccelPeaks': 0.0,
      'analyzedVideos': 0.0,
    };
  }

  group('ComparatorResultDto.fromJson', () {
    test('parses playerA and playerB from JSON', () {
      final json = <String, dynamic>{
        'playerA': <String, dynamic>{
          'aggregated': aggJson(distance: 10000.0, maxSpeed: 32.0),
          'videos': <dynamic>[],
        },
        'playerB': <String, dynamic>{
          'aggregated': aggJson(distance: 9000.0, maxSpeed: 30.0),
          'videos': <dynamic>[],
        },
      };

      final dto = ComparatorResultDto.fromJson(json);
      expect(dto.playerA.aggregated.totalDistanceMeters, 10000.0);
      expect(dto.playerB.aggregated.totalDistanceMeters, 9000.0);
      expect(dto.playerA.aggregated.maxSpeedKmh, 32.0);
    });

    test('handles missing playerA/playerB gracefully', () {
      final dto = ComparatorResultDto.fromJson(const <String, dynamic>{});
      expect(dto.playerA.aggregated.totalDistanceMeters, 0.0);
      expect(dto.playerB.videos, isEmpty);
    });

    test('handles non-typed Map for players', () {
      final json = <String, dynamic>{
        'playerA': <Object?, Object?>{
          'aggregated': <Object?, Object?>{
            'totalDistanceMeters': 5000.0,
            'maxSpeedKmh': 25.0,
            'avgSpeedKmh': 6.0,
            'totalSprints': 10.0,
            'totalAccelPeaks': 2.0,
            'analyzedVideos': 1.0,
          },
          'videos': <dynamic>[],
        },
      };

      final dto = ComparatorResultDto.fromJson(json);
      expect(dto.playerA.aggregated.totalDistanceMeters, 5000.0);
    });
  });

  group('ComparatorResultDto.toJson', () {
    test('serializes to JSON', () {
      final json = <String, dynamic>{
        'playerA': <String, dynamic>{
          'aggregated': aggJson(distance: 10000.0),
          'videos': <dynamic>[],
        },
        'playerB': <String, dynamic>{
          'aggregated': aggJson(distance: 9000.0),
          'videos': <dynamic>[],
        },
      };

      final dto = ComparatorResultDto.fromJson(json);
      final serialized = dto.toJson();
      expect(serialized, containsPair('playerA', isA<Map>()));
      expect(serialized, containsPair('playerB', isA<Map>()));
    });
  });
}
