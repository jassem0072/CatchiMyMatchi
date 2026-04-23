import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../services/analysis_run_service.dart';

final analysisRunServiceProvider = Provider<AnalysisRunService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AnalysisRunService(apiClient);
});
