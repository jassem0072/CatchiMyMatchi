class AnalysisMetricsDto {
  const AnalysisMetricsDto({
    required this.metrics,
    required this.positions,
    required this.distanceKm,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.sprints,
    required this.accelPeaks,
    required this.positionCount,
    required this.heatmapCounts,
    required this.heatGridW,
    required this.heatGridH,
    required this.isCalibrated,
    required this.workRate,
    required this.movingRatio,
    required this.directionChanges,
    required this.matchReadiness,
    required this.movementZones,
    required this.videoId,
    required this.meterPerPx,
  });

  final Map<String, dynamic> metrics;
  final List<dynamic> positions;
  final double distanceKm;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final int sprints;
  final int accelPeaks;
  final int positionCount;
  final List<dynamic>? heatmapCounts;
  final int heatGridW;
  final int heatGridH;
  final bool isCalibrated;
  final double? workRate;
  final double? movingRatio;
  final double? directionChanges;
  final double? matchReadiness;
  final Map<String, dynamic>? movementZones;
  final String? videoId;
  final double meterPerPx;

  factory AnalysisMetricsDto.fromArgs(Map<String, dynamic> args) {
    final metrics = args['metrics'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    final rawPositions = args['positions'];
    final positions = rawPositions is List ? rawPositions : const <dynamic>[];

    final heatmap = metrics['heatmap'] as Map<String, dynamic>?;
    final coordSpace = (heatmap?['coord_space'] as String?) ?? 'image';

    double? workRate = _dblOrNull(metrics['workRateMetersPerMin']);
    double? movingRatio = _dblOrNull(metrics['movingRatio']);
    double? directionChanges = _dblOrNull(metrics['directionChangesPerMin']);
    double? matchReadiness;

    Map<String, dynamic>? movementZones =
        metrics['movementZones'] is Map<String, dynamic>
            ? metrics['movementZones'] as Map<String, dynamic>
            : null;

    final movement = metrics['movement'] as Map<String, dynamic>?;
    if (movement != null) {
      matchReadiness = _dblOrNull(movement['qualityScore'])?.clamp(0.0, 1.0);
      final mz = movement['zones'];
      if (movementZones == null && mz is Map) {
        movementZones = Map<String, dynamic>.from(mz);
      }
      workRate ??= _dblOrNull(movement['workRateMetersPerMin']);
      movingRatio ??= _dblOrNull(movement['movingRatio']);
      directionChanges ??=
          _dblOrNull(movement['dirChangesPerMin'] ?? movement['directionChangesPerMin']);
    }

    final debug = args['debug'] as Map<String, dynamic>?;

    return AnalysisMetricsDto(
      metrics: metrics,
      positions: positions,
      distanceKm: _dbl(metrics['distanceMeters']) / 1000.0,
      maxSpeedKmh: _dbl(metrics['maxSpeedKmh']).clamp(0.0, 45.0),
      avgSpeedKmh: _dbl(metrics['avgSpeedKmh']).clamp(0.0, 45.0),
      sprints: _intVal(metrics['sprintCount']),
      accelPeaks: _intVal(metrics['accelPeaks']),
      positionCount: positions.length,
      heatmapCounts: heatmap?['counts'] as List<dynamic>?,
      heatGridW: _intVal(heatmap?['grid_w']),
      heatGridH: _intVal(heatmap?['grid_h']),
      isCalibrated: coordSpace == 'pitch' ||
          (metrics['distanceMeters'] != null && metrics['maxSpeedKmh'] != null),
      workRate: workRate,
      movingRatio: movingRatio,
      directionChanges: directionChanges,
      matchReadiness: matchReadiness,
      movementZones: movementZones,
      videoId: (args['_videoId'] ?? args['_id'] ?? args['id'])?.toString(),
      meterPerPx: _dbl(debug?['meterPerPx']),
    );
  }

  static double _dbl(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static double? _dblOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int _intVal(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
