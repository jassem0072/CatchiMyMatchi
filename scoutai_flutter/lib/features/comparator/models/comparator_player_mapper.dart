import 'comparator_player.dart';
import 'comparator_player_dto.dart';

class ComparatorPlayerMapper {
  const ComparatorPlayerMapper._();

  static ComparatorPlayer toEntity(ComparatorPlayerDto dto) {
    final emailPrefix = dto.email.contains('@') ? dto.email.split('@').first : '';
    final fallbackName = emailPrefix.isEmpty ? 'Player' : emailPrefix;
    final displayName = dto.displayName.trim().isEmpty ? fallbackName : dto.displayName.trim();

    return ComparatorPlayer(
      id: dto.id,
      displayName: displayName,
      email: dto.email,
      position: dto.position,
      nation: dto.nation,
      playerIdNumber: dto.playerIdNumber,
    );
  }

  static ComparatorPlayerDto toDto(ComparatorPlayer entity) {
    return ComparatorPlayerDto(
      id: entity.id,
      displayName: entity.displayName,
      email: entity.email,
      position: entity.position,
      nation: entity.nation,
      playerIdNumber: entity.playerIdNumber,
    );
  }
}
