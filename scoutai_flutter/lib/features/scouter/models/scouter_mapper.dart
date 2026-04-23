import 'scouter.dart';
import 'scouter_dto.dart';

class ScouterMapper {
  const ScouterMapper._();

  static Scouter toEntity(ScouterDto dto) {
    final emailPrefix = dto.email.contains('@') ? dto.email.split('@').first : '';
    final fallbackName = emailPrefix.isEmpty ? 'Scouter' : emailPrefix;
    final displayName = dto.displayName.trim().isEmpty ? fallbackName : dto.displayName.trim();

    return Scouter(
      id: dto.id,
      displayName: displayName,
      email: dto.email,
      role: dto.role.trim().isEmpty ? 'scouter' : dto.role.trim(),
      nation: dto.nation,
      subscriptionTier: dto.subscriptionTier,
      isVerified: dto.isVerified,
      isPremium: dto.isPremium,
    );
  }

  static ScouterDto toDto(Scouter entity) {
    return ScouterDto(
      id: entity.id,
      displayName: entity.displayName,
      email: entity.email,
      role: entity.role,
      nation: entity.nation,
      subscriptionTier: entity.subscriptionTier,
      isVerified: entity.isVerified,
      isPremium: entity.isPremium,
    );
  }
}
