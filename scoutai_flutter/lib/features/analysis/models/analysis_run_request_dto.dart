import 'analysis_selection_dto.dart';

class AnalysisRunRequestDto {
  const AnalysisRunRequestDto({
    required this.videoId,
    required this.selection,
    required this.samplingFps,
  });

  final String videoId;
  final AnalysisSelectionDto selection;
  final int samplingFps;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'videoId': videoId,
      'selection': selection.toJson(),
      'samplingFps': samplingFps,
    };
  }
}
