import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/analysis/models/analysis_metrics_dto.dart';

void main() {
  group('AnalysisMetricsDto.fromArgs', () {
    test('parses complete args correctly', () {
      final args = <String, dynamic>{
        'metrics': <String, dynamic>{
          'distanceMeters': 10500.0,
          'maxSpeedKmh': 33.5,
          'avgSpeedKmh': 8.2,
          'sprintCount': 22,
          'accelPeaks': 7,
          'heatmap': <String, dynamic>{
            'counts': [1, 2, 3],
            'grid_w': 10,
            'grid_h': 8,
            'coord_space': 'pitch',
          },
        },
        'positions': [
          {'cx': 100, 'cy': 200, 't': 0.0},
          {'cx': 110, 'cy': 210, 't': 0.5},
        ],
        '_videoId': 'vid1',
        'debug': <String, dynamic>{
          'meterPerPx': 0.15,
        },
      };

      final dto = AnalysisMetricsDto.fromArgs(args);
      expect(dto.distanceKm, closeTo(10.5, 0.01));
      expect(dto.maxSpeedKmh, 33.5);
      expect(dto.avgSpeedKmh, 8.2);
      expect(dto.sprints, 22);
      expect(dto.accelPeaks, 7);
      expect(dto.positionCount, 2);
      expect(dto.heatmapCounts, [1, 2, 3]);
      expect(dto.heatGridW, 10);
      expect(dto.heatGridH, 8);
      expect(dto.isCalibrated, true);
      expect(dto.videoId, 'vid1');
      expect(dto.meterPerPx, 0.15);
    });

    test('defaults to zero for missing metrics', () {
      final dto = AnalysisMetricsDto.fromArgs(const <String, dynamic>{});
      expect(dto.distanceKm, 0.0);
      expect(dto.maxSpeedKmh, 0.0);
      expect(dto.avgSpeedKmh, 0.0);
      expect(dto.sprints, 0);
      expect(dto.accelPeaks, 0);
      expect(dto.positionCount, 0);
      expect(dto.heatmapCounts, isNull);
      expect(dto.isCalibrated, false);
    });

    test('clamps maxSpeedKmh to 45', () {
      final args = <String, dynamic>{
        'metrics': <String, dynamic>{
          'maxSpeedKmh': 99.0,
          'avgSpeedKmh': 50.0,
        },
      };

      final dto = AnalysisMetricsDto.fromArgs(args);
      expect(dto.maxSpeedKmh, 45.0);
      expect(dto.avgSpeedKmh, 45.0);
    });

    test('reads movement data for workRate and matchReadiness', () {
      final args = <String, dynamic>{
        'metrics': <String, dynamic>{
          'movement': <String, dynamic>{
            'workRateMetersPerMin': 85.0,
            'movingRatio': 0.65,
            'dirChangesPerMin': 3.2,
            'qualityScore': 0.8,
            'zones': <String, dynamic>{
              'walking': 40.0,
              'jogging': 30.0,
              'sprinting': 30.0,
            },
          },
        },
      };

      final dto = AnalysisMetricsDto.fromArgs(args);
      expect(dto.workRate, 85.0);
      expect(dto.movingRatio, 0.65);
      expect(dto.directionChanges, 3.2);
      expect(dto.matchReadiness, 0.8);
      expect(dto.movementZones, isNotNull);
      expect(dto.movementZones!['walking'], 40.0);
    });

    test('clamps matchReadiness to 0..1', () {
      final args = <String, dynamic>{
        'metrics': <String, dynamic>{
          'movement': <String, dynamic>{
            'qualityScore': 1.5,
          },
        },
      };

      final dto = AnalysisMetricsDto.fromArgs(args);
      expect(dto.matchReadiness, 1.0);
    });

    test('isCalibrated true when distanceMeters and maxSpeedKmh present', () {
      final args = <String, dynamic>{
        'metrics': <String, dynamic>{
          'distanceMeters': 5000.0,
          'maxSpeedKmh': 25.0,
        },
      };

      final dto = AnalysisMetricsDto.fromArgs(args);
      expect(dto.isCalibrated, true);
    });

    test('reads videoId from fallback fields', () {
      final args1 = <String, dynamic>{'_id': 'a'};
      expect(AnalysisMetricsDto.fromArgs(args1).videoId, 'a');

      final args2 = <String, dynamic>{'id': 'b'};
      expect(AnalysisMetricsDto.fromArgs(args2).videoId, 'b');
    });

    test('handles positions as non-list gracefully', () {
      final args = <String, dynamic>{
        'positions': 'not a list',
      };

      final dto = AnalysisMetricsDto.fromArgs(args);
      expect(dto.positions, isEmpty);
      expect(dto.positionCount, 0);
    });
  });
}
