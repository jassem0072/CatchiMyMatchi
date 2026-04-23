import 'comparator_video_metrics_dto.dart';

class ComparatorVideoEntryDto {
  const ComparatorVideoEntryDto({
    required this.originalName,
    required this.metrics,
  });

  final String originalName;
  final ComparatorVideoMetricsDto metrics;

  factory ComparatorVideoEntryDto.fromJson(Map<String, dynamic> json) {
    final metricsRaw = json['metrics'];
    return ComparatorVideoEntryDto(
      originalName: (json['originalName'] ?? 'Video').toString(),
      metrics: metricsRaw is Map<String, dynamic>
          ? ComparatorVideoMetricsDto.fromJson(metricsRaw)
          : metricsRaw is Map
              ? ComparatorVideoMetricsDto.fromJson(Map<String, dynamic>.from(metricsRaw))
              : const ComparatorVideoMetricsDto.empty(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'originalName': originalName,
      'metrics': metrics.toJson(),
    };
  }
}
