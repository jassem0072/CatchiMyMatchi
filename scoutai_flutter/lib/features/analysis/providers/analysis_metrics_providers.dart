import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/analysis_metrics_service.dart';

final analysisMetricsServiceProvider = Provider<AnalysisMetricsService>((ref) {
  return const AnalysisMetricsService();
});
