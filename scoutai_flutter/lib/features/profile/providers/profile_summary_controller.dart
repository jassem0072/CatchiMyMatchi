import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile_summary.dart';
import 'profile_providers.dart';

class ProfileSummaryController extends AutoDisposeAsyncNotifier<ProfileSummary> {
  @override
  Future<ProfileSummary> build() async {
    return ref.read(profileServiceProvider).loadProfileSummary();
  }

  Future<void> refreshSummary() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return ref.read(profileServiceProvider).loadProfileSummary();
    });
  }
}

final profileSummaryControllerProvider =
    AutoDisposeAsyncNotifierProvider<ProfileSummaryController, ProfileSummary>(
  ProfileSummaryController.new,
);
