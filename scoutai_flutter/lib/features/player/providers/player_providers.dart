import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/player.dart';
import '../models/player_video.dart';
import '../services/player_service.dart';

final playerServiceProvider = Provider<PlayerService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PlayerService(apiClient);
});

final currentPlayerProvider = FutureProvider<Player>((ref) async {
  final service = ref.watch(playerServiceProvider);
  return service.getCurrentPlayer();
});

final currentPlayerVideosProvider = FutureProvider<List<PlayerVideo>>((ref) async {
  final service = ref.watch(playerServiceProvider);
  return service.getCurrentPlayerVideos();
});
