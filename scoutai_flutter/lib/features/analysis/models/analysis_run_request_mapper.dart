import 'analysis_run_request.dart';
import 'analysis_run_request_dto.dart';
import 'analysis_selection_mapper.dart';

class AnalysisRunRequestMapper {
  const AnalysisRunRequestMapper._();

  static AnalysisRunRequestDto toDto(AnalysisRunRequest entity) {
    return AnalysisRunRequestDto(
      videoId: entity.videoId,
      selection: AnalysisSelectionMapper.toDto(entity.selection),
      samplingFps: entity.samplingFps,
    );
  }
}
