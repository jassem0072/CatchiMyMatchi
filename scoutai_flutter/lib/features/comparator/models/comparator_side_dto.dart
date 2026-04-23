import 'comparator_aggregated_metrics_dto.dart';
import 'comparator_video_entry_dto.dart';

class ComparatorSideDto {
  const ComparatorSideDto({
    required this.aggregated,
    required this.videos,
  });

  final ComparatorAggregatedMetricsDto aggregated;
  final List<ComparatorVideoEntryDto> videos;

  factory ComparatorSideDto.fromJson(Map<String, dynamic> json) {
    final aggregatedRaw = json['aggregated'];
    final videosRaw = json['videos'];

    return ComparatorSideDto(
      aggregated: aggregatedRaw is Map<String, dynamic>
          ? ComparatorAggregatedMetricsDto.fromJson(aggregatedRaw)
          : aggregatedRaw is Map
              ? ComparatorAggregatedMetricsDto.fromJson(Map<String, dynamic>.from(aggregatedRaw))
              : const ComparatorAggregatedMetricsDto.empty(),
      videos: videosRaw is List
          ? videosRaw
              .whereType<Map>()
              .map((v) => ComparatorVideoEntryDto.fromJson(Map<String, dynamic>.from(v)))
              .toList()
          : const <ComparatorVideoEntryDto>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'aggregated': aggregated.toJson(),
      'videos': videos.map((v) => v.toJson()).toList(),
    };
  }
}
