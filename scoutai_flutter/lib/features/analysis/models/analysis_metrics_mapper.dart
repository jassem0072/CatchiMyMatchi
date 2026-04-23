import 'analysis_metrics.dart';
import 'analysis_metrics_dto.dart';

class AnalysisMetricsMapper {
  const AnalysisMetricsMapper._();

  static AnalysisMetrics toEntity(AnalysisMetricsDto dto) {
    return AnalysisMetrics(
      metrics: dto.metrics,
      positions: dto.positions,
      distanceKm: dto.distanceKm,
      maxSpeedKmh: dto.maxSpeedKmh,
      avgSpeedKmh: dto.avgSpeedKmh,
      sprints: dto.sprints,
      accelPeaks: dto.accelPeaks,
      positionCount: dto.positionCount,
      heatmapCounts: dto.heatmapCounts,
      heatGridW: dto.heatGridW,
      heatGridH: dto.heatGridH,
      isCalibrated: dto.isCalibrated,
      workRate: dto.workRate,
      movingRatio: dto.movingRatio,
      directionChanges: dto.directionChanges,
      matchReadiness: dto.matchReadiness,
      movementZones: dto.movementZones,
      videoId: dto.videoId,
      meterPerPx: dto.meterPerPx,
    );
  }
}
