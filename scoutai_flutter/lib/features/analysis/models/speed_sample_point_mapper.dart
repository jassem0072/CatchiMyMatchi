import 'speed_sample_point.dart';
import 'speed_sample_point_dto.dart';

class SpeedSamplePointMapper {
  const SpeedSamplePointMapper._();

  static SpeedSamplePoint toEntity(SpeedSamplePointDto dto) {
    return SpeedSamplePoint(
      t: dto.t,
      kmh: dto.kmh,
    );
  }

  static SpeedSamplePointDto toDto(SpeedSamplePoint entity) {
    return SpeedSamplePointDto(
      t: entity.t,
      kmh: entity.kmh,
    );
  }
}
