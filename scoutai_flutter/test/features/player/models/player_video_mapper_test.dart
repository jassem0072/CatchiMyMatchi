import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/player/models/player_video.dart';
import 'package:scoutai/features/player/models/player_video_dto.dart';
import 'package:scoutai/features/player/models/player_video_mapper.dart';

void main() {
  group('PlayerVideoMapper.toEntity', () {
    test('maps DTO to entity with analysis', () {
      const dto = PlayerVideoDto(
        id: 'v1',
        originalName: 'match.mp4',
        createdAt: null,
        lastAnalysis: PlayerVideoAnalysisDto(
          distanceKm: 10.0,
          maxSpeedKmh: 32.0,
          sprints: 18,
        ),
      );

      final entity = PlayerVideoMapper.toEntity(dto);
      expect(entity, isA<PlayerVideo>());
      expect(entity.id, 'v1');
      expect(entity.originalName, 'match.mp4');
      expect(entity.lastAnalysis, isNotNull);
      expect(entity.lastAnalysis!.distanceKm, 10.0);
      expect(entity.lastAnalysis!.maxSpeedKmh, 32.0);
      expect(entity.lastAnalysis!.sprints, 18);
    });

    test('maps DTO to entity without analysis', () {
      const dto = PlayerVideoDto(
        id: 'v2',
        originalName: 'clip.mp4',
        createdAt: null,
        lastAnalysis: null,
      );

      final entity = PlayerVideoMapper.toEntity(dto);
      expect(entity.id, 'v2');
      expect(entity.lastAnalysis, isNull);
    });

    test('preserves createdAt', () {
      final date = DateTime(2025, 3, 15, 10, 30);
      final dto = PlayerVideoDto(
        id: 'v3',
        originalName: 'game.mp4',
        createdAt: date,
      );

      final entity = PlayerVideoMapper.toEntity(dto);
      expect(entity.createdAt, date);
    });
  });
}
