import 'comparator_aggregated_metrics_mapper.dart';
import 'comparator_side.dart';
import 'comparator_side_dto.dart';
import 'comparator_video_entry_mapper.dart';

class ComparatorSideMapper {
  const ComparatorSideMapper._();

  static ComparatorSide toEntity(ComparatorSideDto dto) {
    return ComparatorSide(
      aggregated: ComparatorAggregatedMetricsMapper.toEntity(dto.aggregated),
      videos: dto.videos.map(ComparatorVideoEntryMapper.toEntity).toList(),
    );
  }

  static ComparatorSideDto toDto(ComparatorSide entity) {
    return ComparatorSideDto(
      aggregated: ComparatorAggregatedMetricsMapper.toDto(entity.aggregated),
      videos: entity.videos.map(ComparatorVideoEntryMapper.toDto).toList(),
    );
  }
}
