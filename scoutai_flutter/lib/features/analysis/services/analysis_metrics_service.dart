import 'dart:math' as math;

import '../models/speed_sample_point.dart';

class AnalysisMetricsService {
  const AnalysisMetricsService();

  List<SpeedSamplePoint> buildSpeedSamples({
    required List<dynamic> positions,
    required double meterPerPx,
    double fallbackMeterPerPx = 0.1,
    double maxHumanSpeedKmh = 45.0,
  }) {
    if (positions.length < 2) return const <SpeedSamplePoint>[];

    final samples = <SpeedSamplePoint>[];
    for (int i = 1; i < positions.length; i++) {
      final curRaw = positions[i];
      final prevRaw = positions[i - 1];
      if (curRaw is! Map || prevRaw is! Map) continue;

      final cur = Map<String, dynamic>.from(curRaw);
      final prev = Map<String, dynamic>.from(prevRaw);

      final dt = _dbl(cur['t']) - _dbl(prev['t']);
      if (dt <= 0) continue;

      final dx = _dbl(cur['cx']) - _dbl(prev['cx']);
      final dy = _dbl(cur['cy']) - _dbl(prev['cy']);
      final distPx = math.sqrt(dx * dx + dy * dy);

      final ratio = meterPerPx > 0 ? meterPerPx : fallbackMeterPerPx;
      final speedKmh = ((distPx * ratio / dt) * 3.6).clamp(0.0, maxHumanSpeedKmh);

      samples.add(
        SpeedSamplePoint(
          t: _dbl(cur['t']),
          kmh: speedKmh,
        ),
      );
    }

    return samples;
  }

  static double _dbl(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
