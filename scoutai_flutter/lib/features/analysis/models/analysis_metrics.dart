class AnalysisMetrics {
  const AnalysisMetrics({
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
}
