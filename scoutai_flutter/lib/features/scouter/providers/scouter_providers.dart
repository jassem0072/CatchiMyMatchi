import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/scouter.dart';
import '../models/scouter_player.dart';
import '../models/scouter_player_workflow.dart';
import '../services/scouter_service.dart';

final scouterServiceProvider = Provider<ScouterService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ScouterService(apiClient);
});

final currentScouterProvider = FutureProvider.autoDispose<Scouter>((ref) {
  return ref.watch(scouterServiceProvider).getCurrentScouter();
});

final favoriteScouterPlayersProvider = FutureProvider.autoDispose<List<ScouterPlayer>>((ref) {
  return ref.watch(scouterServiceProvider).getFavoritePlayers();
});

final scouterPlayerWorkflowProvider =
    FutureProvider.autoDispose.family<ScouterPlayerWorkflow?, String>((ref, playerId) {
  return ref.watch(scouterServiceProvider).getScouterPlayerWorkflow(playerId);
});
