import '../../../core/network/api_client.dart';
import '../models/analysis_run_request.dart';
import '../models/analysis_run_request_mapper.dart';
import '../models/analysis_run_result.dart';
import '../models/analysis_run_result_dto.dart';
import '../models/analysis_run_result_mapper.dart';

class AnalysisRunService {
  AnalysisRunService(this._apiClient);

  final ApiClient _apiClient;

  Future<AnalysisRunResult> runAnalysis(AnalysisRunRequest request) async {
    final safeVideoId = request.videoId.trim();
    if (safeVideoId.isEmpty) {
      throw Exception('Missing videoId');
    }

    final dto = AnalysisRunRequestMapper.toDto(request);
    final body = <String, dynamic>{
      'selection': dto.selection.toJson(),
      'samplingFps': dto.samplingFps,
    };

    final data = await _apiClient.post('/videos/$safeVideoId/analyze', body: body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid analysis payload');
    }

    return AnalysisRunResultMapper.toEntity(AnalysisRunResultDto.fromJson(data));
  }
}
