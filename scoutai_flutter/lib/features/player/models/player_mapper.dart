import 'player.dart';
import 'player_dto.dart';

class PlayerMapper {
  const PlayerMapper._();

  static Player toEntity(PlayerDto dto) {
    final emailPrefix = dto.email.contains('@') ? dto.email.split('@').first : '';
    final fallbackName = emailPrefix.isEmpty ? 'Player' : emailPrefix;
    final displayName = dto.displayName.trim().isEmpty ? fallbackName : dto.displayName.trim();
    return Player(
      id: dto.id,
      displayName: displayName,
      email: dto.email,
      position: dto.position,
      nation: dto.nation,
    );
  }

  static PlayerDto toDto(Player entity) {
    return PlayerDto(
      id: entity.id,
      displayName: entity.displayName,
      email: entity.email,
      position: entity.position,
      nation: entity.nation,
    );
  }
}
