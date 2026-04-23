import 'analysis_selection.dart';
import 'analysis_selection_dto.dart';

class AnalysisSelectionMapper {
  const AnalysisSelectionMapper._();

  static AnalysisSelection toEntity(AnalysisSelectionDto dto) {
    return AnalysisSelection(
      t0: dto.t0,
      x: dto.x,
      y: dto.y,
      w: dto.w,
      h: dto.h,
    );
  }

  static AnalysisSelectionDto toDto(AnalysisSelection entity) {
    return AnalysisSelectionDto(
      t0: entity.t0,
      x: entity.x,
      y: entity.y,
      w: entity.w,
      h: entity.h,
    );
  }
}
