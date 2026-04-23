import 'player_video.dart';
import 'player_video_dto.dart';

class PlayerVideoMapper {
  const PlayerVideoMapper._();

  static PlayerVideo toEntity(PlayerVideoDto dto) {
    return PlayerVideo(
      id: dto.id,
      originalName: dto.originalName,
      createdAt: dto.createdAt,
      lastAnalysis: dto.lastAnalysis == null ? null : _toAnalysisEntity(dto.lastAnalysis!),
    );
  }

  static PlayerVideoAnalysis _toAnalysisEntity(PlayerVideoAnalysisDto dto) {
    return PlayerVideoAnalysis(
      distanceKm: dto.distanceKm,
      maxSpeedKmh: dto.maxSpeedKmh,
      sprints: dto.sprints,
    );
  }
}
