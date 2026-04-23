import '../../../core/network/api_client.dart';
import '../../player/models/player.dart';
import '../../player/models/player_dto.dart';
import '../../player/models/player_mapper.dart';
import '../models/profile_summary.dart';
import '../models/profile_summary_dto.dart';
import '../models/profile_summary_mapper.dart';

class ProfileService {
  ProfileService(this._apiClient);

  final ApiClient _apiClient;

  Future<ProfileSummary> loadProfileSummary() async {
    final meData = await _apiClient.get('/me');
    if (meData is! Map<String, dynamic>) {
      throw Exception('Invalid /me payload');
    }

    final portraitRes = await _apiClient.getBytes(
      '/me/portrait',
      query: {'ts': DateTime.now().millisecondsSinceEpoch.toString()},
    );

    final contentType = (portraitRes.headers['content-type'] ?? '').toLowerCase();
    final portraitBytes = (portraitRes.bodyBytes.isNotEmpty && contentType.startsWith('image/'))
        ? portraitRes.bodyBytes
        : null;

    final videosData = await _apiClient.get('/me/videos');
    final videos = videosData is List ? videosData : const <dynamic>[];

    final dto = ProfileSummaryDto.fromParts(
      meJson: meData,
      portraitBytes: portraitBytes,
      videos: videos,
    );

    return ProfileSummaryMapper.toEntity(dto);
  }

  Future<Player> getCurrentPlayer() async {
    final data = await _apiClient.get('/me');
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid /me payload');
    }
    return PlayerMapper.toEntity(PlayerDto.fromJson(data));
  }
}
