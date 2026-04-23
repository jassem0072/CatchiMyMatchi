import 'comparator_video_metrics.dart';
import 'comparator_video_metrics_dto.dart';

class ComparatorVideoMetricsMapper {
  const ComparatorVideoMetricsMapper._();

  static ComparatorVideoMetrics toEntity(ComparatorVideoMetricsDto dto) {
    return ComparatorVideoMetrics(
      distanceMeters: dto.distanceMeters,
      avgSpeedKmh: dto.avgSpeedKmh,
      maxSpeedKmh: dto.maxSpeedKmh,
      sprintCount: dto.sprintCount,
    );
  }

  static ComparatorVideoMetricsDto toDto(ComparatorVideoMetrics entity) {
    return ComparatorVideoMetricsDto(
      distanceMeters: entity.distanceMeters,
      avgSpeedKmh: entity.avgSpeedKmh,
      maxSpeedKmh: entity.maxSpeedKmh,
      sprintCount: entity.sprintCount,
    );
  }
}
