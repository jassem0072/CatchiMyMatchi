import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/player/models/player_dto.dart';
import 'package:scoutai/features/profile/models/profile_summary_dto.dart';
import 'package:scoutai/features/profile/models/profile_summary_mapper.dart';

void main() {
  group('ProfileSummaryMapper.toEntity', () {
    test('maps DTO to entity using PlayerMapper', () {
      final dto = ProfileSummaryDto(
        playerDto: const PlayerDto(
          id: 'p1',
          displayName: 'John',
          email: 'john@test.com',
          position: 'ST',
          nation: 'France',
        ),
        meRaw: const <String, dynamic>{'_id': 'p1'},
        portraitBytes: Uint8List.fromList([1, 2, 3]),
        videos: const [
          {'_id': 'v1'},
        ],
      );

      final entity = ProfileSummaryMapper.toEntity(dto);
      expect(entity.player.id, 'p1');
      expect(entity.player.displayName, 'John');
      expect(entity.meRaw['_id'], 'p1');
      expect(entity.portraitBytes, hasLength(3));
      expect(entity.videos, hasLength(1));
    });

    test('applies PlayerMapper displayName fallback', () {
      final dto = ProfileSummaryDto(
        playerDto: const PlayerDto(
          id: 'p2',
          displayName: '',
          email: 'fallback@example.com',
          position: 'GK',
          nation: '',
        ),
        meRaw: const <String, dynamic>{},
        portraitBytes: null,
        videos: const [],
      );

      final entity = ProfileSummaryMapper.toEntity(dto);
      expect(entity.player.displayName, 'fallback');
    });
  });
}
