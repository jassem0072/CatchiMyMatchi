import 'analysis_selection.dart';

class AnalysisRunRequest {
  const AnalysisRunRequest({
    required this.videoId,
    required this.selection,
    this.samplingFps = 4,
  });

  final String videoId;
  final AnalysisSelection selection;
  final int samplingFps;
}
