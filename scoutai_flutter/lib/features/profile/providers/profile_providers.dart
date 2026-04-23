import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/profile_summary.dart';
import '../services/profile_service.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ProfileService(apiClient);
});

final profileSummaryProvider = FutureProvider<ProfileSummary>((ref) async {
  final service = ref.watch(profileServiceProvider);
  return service.loadProfileSummary();
});
