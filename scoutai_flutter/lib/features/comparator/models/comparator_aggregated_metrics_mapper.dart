import 'comparator_aggregated_metrics.dart';
import 'comparator_aggregated_metrics_dto.dart';

class ComparatorAggregatedMetricsMapper {
  const ComparatorAggregatedMetricsMapper._();

  static ComparatorAggregatedMetrics toEntity(ComparatorAggregatedMetricsDto dto) {
    return ComparatorAggregatedMetrics(
      totalDistanceMeters: dto.totalDistanceMeters,
      avgSpeedKmh: dto.avgSpeedKmh,
      maxSpeedKmh: dto.maxSpeedKmh,
      totalSprints: dto.totalSprints,
      totalAccelPeaks: dto.totalAccelPeaks,
      analyzedVideos: dto.analyzedVideos,
    );
  }

  static ComparatorAggregatedMetricsDto toDto(ComparatorAggregatedMetrics entity) {
    return ComparatorAggregatedMetricsDto(
      totalDistanceMeters: entity.totalDistanceMeters,
      avgSpeedKmh: entity.avgSpeedKmh,
      maxSpeedKmh: entity.maxSpeedKmh,
      totalSprints: entity.totalSprints,
      totalAccelPeaks: entity.totalAccelPeaks,
      analyzedVideos: entity.analyzedVideos,
    );
  }
}
