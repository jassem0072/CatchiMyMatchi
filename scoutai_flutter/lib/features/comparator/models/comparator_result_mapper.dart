import 'comparator_result.dart';
import 'comparator_result_dto.dart';
import 'comparator_side_mapper.dart';

class ComparatorResultMapper {
  const ComparatorResultMapper._();

  static ComparatorResult toEntity(ComparatorResultDto dto) {
    return ComparatorResult(
      playerA: ComparatorSideMapper.toEntity(dto.playerA),
      playerB: ComparatorSideMapper.toEntity(dto.playerB),
    );
  }

  static ComparatorResultDto toDto(ComparatorResult entity) {
    return ComparatorResultDto(
      playerA: ComparatorSideMapper.toDto(entity.playerA),
      playerB: ComparatorSideMapper.toDto(entity.playerB),
    );
  }
}
