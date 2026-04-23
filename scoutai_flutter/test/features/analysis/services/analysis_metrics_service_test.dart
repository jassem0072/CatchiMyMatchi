import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/analysis/services/analysis_metrics_service.dart';

void main() {
  const service = AnalysisMetricsService();

  group('AnalysisMetricsService.buildSpeedSamples', () {
    test('returns empty for less than 2 positions', () {
      final result = service.buildSpeedSamples(positions: [{'cx': 0, 'cy': 0, 't': 0}], meterPerPx: 0.1);
      expect(result, isEmpty);
    });

    test('computes speed samples from positions', () {
      final positions = [
        {'cx': 0.0, 'cy': 0.0, 't': 0.0},
        {'cx': 100.0, 'cy': 0.0, 't': 1.0},
      ];
      final result = service.buildSpeedSamples(positions: positions, meterPerPx: 0.1);
      expect(result, hasLength(1));
      expect(result[0].t, 1.0);
      // 100px * 0.1m/px / 1s = 10 m/s = 36 km/h
      expect(result[0].kmh, closeTo(36.0, 0.01));
    });

    test('clamps to maxHumanSpeedKmh', () {
      final positions = [
        {'cx': 0.0, 'cy': 0.0, 't': 0.0},
        {'cx': 10000.0, 'cy': 0.0, 't': 0.1},
      ];
      final result = service.buildSpeedSamples(positions: positions, meterPerPx: 1.0);
      expect(result[0].kmh, 45.0);
    });

    test('skips zero or negative time delta', () {
      final positions = [
        {'cx': 0, 'cy': 0, 't': 1.0},
        {'cx': 10, 'cy': 0, 't': 1.0},
        {'cx': 20, 'cy': 0, 't': 0.5},
      ];
      final result = service.buildSpeedSamples(positions: positions, meterPerPx: 0.1);
      expect(result, isEmpty);
    });

    test('uses fallbackMeterPerPx when meterPerPx is 0', () {
      final positions = [
        {'cx': 0.0, 'cy': 0.0, 't': 0.0},
        {'cx': 10.0, 'cy': 0.0, 't': 1.0},
      ];
      final result = service.buildSpeedSamples(positions: positions, meterPerPx: 0, fallbackMeterPerPx: 0.5);
      expect(result, hasLength(1));
      // 10px * 0.5m/px / 1s = 5 m/s = 18 km/h
      expect(result[0].kmh, closeTo(18.0, 0.01));
    });

    test('skips non-Map entries', () {
      final positions = [
        {'cx': 0, 'cy': 0, 't': 0.0},
        'not a map',
        {'cx': 10, 'cy': 0, 't': 1.0},
      ];
      final result = service.buildSpeedSamples(positions: positions, meterPerPx: 0.1);
      expect(result, isEmpty);
    });
  });
}
