import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import '../models/comparator_player.dart';
import '../models/comparator_player_dto.dart';
import '../models/comparator_player_mapper.dart';
import '../models/comparator_result.dart';
import '../models/comparator_result_dto.dart';
import '../models/comparator_result_mapper.dart';

class ComparatorService {
  ComparatorService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ComparatorPlayer>> getPlayers() async {
    final data = await _apiClient.get('/players');
    if (data is! List) return const <ComparatorPlayer>[];

    return data
        .whereType<Map>()
        .map(
          (item) => ComparatorPlayerMapper.toEntity(
            ComparatorPlayerDto.fromJson(Map<String, dynamic>.from(item)),
          ),
        )
        .toList();
  }

  Future<ComparatorResult> comparePlayers({
    required String playerIdA,
    required String playerIdB,
  }) async {
    final data = await _apiClient.post(
      '/players/compare',
      body: <String, dynamic>{
        'playerIdA': playerIdA,
        'playerIdB': playerIdB,
      },
    );

    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid compare payload');
    }

    return ComparatorResultMapper.toEntity(ComparatorResultDto.fromJson(data));
  }

  Future<Uint8List?> getPlayerPortrait(String playerId) async {
    final id = playerId.trim();
    if (id.isEmpty) return null;

    final response = await _apiClient.getBytes('/players/$id/portrait');
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (response.bodyBytes.isEmpty || !contentType.startsWith('image/')) {
      return null;
    }
    return response.bodyBytes;
  }
}
