import 'scouter_player.dart';
import 'scouter_player_dto.dart';

class ScouterPlayerMapper {
  const ScouterPlayerMapper._();

  static ScouterPlayer toEntity(ScouterPlayerDto dto) {
    final emailPrefix = dto.email.contains('@') ? dto.email.split('@').first : '';
    final fallbackName = emailPrefix.isEmpty ? 'Player' : emailPrefix;
    final displayName = dto.displayName.trim().isEmpty ? fallbackName : dto.displayName.trim();

    return ScouterPlayer(
      id: dto.id,
      displayName: displayName,
      email: dto.email,
      playerIdNumber: dto.playerIdNumber,
      position: dto.position,
      nation: dto.nation,
      isFavorite: dto.isFavorite,
      hasAdminWorkflow: dto.hasAdminWorkflow,
    );
  }

  static ScouterPlayerDto toDto(ScouterPlayer entity) {
    return ScouterPlayerDto(
      id: entity.id,
      displayName: entity.displayName,
      email: entity.email,
      playerIdNumber: entity.playerIdNumber,
      position: entity.position,
      nation: entity.nation,
      isFavorite: entity.isFavorite,
      hasAdminWorkflow: entity.hasAdminWorkflow,
    );
  }
}
