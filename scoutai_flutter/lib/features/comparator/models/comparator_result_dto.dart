import 'comparator_aggregated_metrics_dto.dart';
import 'comparator_side_dto.dart';
import 'comparator_video_entry_dto.dart';

class ComparatorResultDto {
  const ComparatorResultDto({
    required this.playerA,
    required this.playerB,
  });

  final ComparatorSideDto playerA;
  final ComparatorSideDto playerB;

  factory ComparatorResultDto.fromJson(Map<String, dynamic> json) {
    final playerARaw = json['playerA'];
    final playerBRaw = json['playerB'];

    return ComparatorResultDto(
      playerA: playerARaw is Map<String, dynamic>
          ? ComparatorSideDto.fromJson(playerARaw)
          : playerARaw is Map
              ? ComparatorSideDto.fromJson(Map<String, dynamic>.from(playerARaw))
              : const ComparatorSideDto(
                  aggregated: ComparatorAggregatedMetricsDto.empty(),
                  videos: <ComparatorVideoEntryDto>[],
                ),
      playerB: playerBRaw is Map<String, dynamic>
          ? ComparatorSideDto.fromJson(playerBRaw)
          : playerBRaw is Map
              ? ComparatorSideDto.fromJson(Map<String, dynamic>.from(playerBRaw))
              : const ComparatorSideDto(
                  aggregated: ComparatorAggregatedMetricsDto.empty(),
                  videos: <ComparatorVideoEntryDto>[],
                ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'playerA': playerA.toJson(),
      'playerB': playerB.toJson(),
    };
  }
}
