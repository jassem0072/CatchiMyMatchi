import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/player.dart';
import '../models/player_dto.dart';
import '../models/player_mapper.dart';
import '../models/player_video.dart';
import '../models/player_video_dto.dart';
import '../models/player_video_mapper.dart';

class PlayerService {
  PlayerService(this._apiClient);

  final ApiClient _apiClient;

  Future<Player> getCurrentPlayer() async {
    final data = await _apiClient.get('/me');
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid /me payload');
    }
    final dto = PlayerDto.fromJson(data);
    return PlayerMapper.toEntity(dto);
  }

  Future<List<PlayerVideo>> getCurrentPlayerVideos() async {
    dynamic data;
    try {
      data = await _apiClient.get('/me/videos');
    } on ApiException catch (e) {
      if (e.statusCode != 403) rethrow;
      data = await _apiClient.get('/videos');
    }

    if (data is! List) {
      throw Exception('Invalid videos payload');
    }

    return data
        .whereType<Map>()
        .map((item) => PlayerVideoMapper.toEntity(
              PlayerVideoDto.fromJson(Map<String, dynamic>.from(item)),
            ))
        .toList(growable: false);
  }
}
