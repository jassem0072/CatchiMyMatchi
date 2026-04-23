import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../services/comparator_service.dart';

final comparatorServiceProvider = Provider<ComparatorService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ComparatorService(apiClient);
});
