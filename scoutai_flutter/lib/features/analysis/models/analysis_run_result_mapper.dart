import 'analysis_run_result.dart';
import 'analysis_run_result_dto.dart';

class AnalysisRunResultMapper {
  const AnalysisRunResultMapper._();

  static AnalysisRunResult toEntity(AnalysisRunResultDto dto) {
    return AnalysisRunResult(raw: dto.raw);
  }
}
