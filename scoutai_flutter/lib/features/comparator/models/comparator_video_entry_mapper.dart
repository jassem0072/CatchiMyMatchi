import 'comparator_video_entry.dart';
import 'comparator_video_entry_dto.dart';
import 'comparator_video_metrics_mapper.dart';

class ComparatorVideoEntryMapper {
  const ComparatorVideoEntryMapper._();

  static ComparatorVideoEntry toEntity(ComparatorVideoEntryDto dto) {
    return ComparatorVideoEntry(
      originalName: dto.originalName,
      metrics: ComparatorVideoMetricsMapper.toEntity(dto.metrics),
    );
  }

  static ComparatorVideoEntryDto toDto(ComparatorVideoEntry entity) {
    return ComparatorVideoEntryDto(
      originalName: entity.originalName,
      metrics: ComparatorVideoMetricsMapper.toDto(entity.metrics),
    );
  }
}
