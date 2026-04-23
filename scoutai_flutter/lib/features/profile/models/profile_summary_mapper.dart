import '../../player/models/player_mapper.dart';
import 'profile_summary.dart';
import 'profile_summary_dto.dart';

class ProfileSummaryMapper {
  const ProfileSummaryMapper._();

  static ProfileSummary toEntity(ProfileSummaryDto dto) {
    return ProfileSummary(
      player: PlayerMapper.toEntity(dto.playerDto),
      meRaw: dto.meRaw,
      portraitBytes: dto.portraitBytes,
      videos: dto.videos,
    );
  }
}
