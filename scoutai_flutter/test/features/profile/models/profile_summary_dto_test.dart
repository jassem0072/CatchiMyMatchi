import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/profile/models/profile_summary_dto.dart';

void main() {
  group('ProfileSummaryDto.fromParts', () {
    test('creates DTO from parts', () {
      final meJson = <String, dynamic>{
        '_id': 'p1',
        'displayName': 'Test User',
        'email': 'test@test.com',
        'position': 'ST',
        'nation': 'France',
      };
      final bytes = Uint8List.fromList([1, 2, 3]);
      final videos = [
        {'_id': 'v1', 'originalName': 'video.mp4'},
      ];

      final dto = ProfileSummaryDto.fromParts(
        meJson: meJson,
        portraitBytes: bytes,
        videos: videos,
      );

      expect(dto.playerDto.id, 'p1');
      expect(dto.playerDto.displayName, 'Test User');
      expect(dto.meRaw, meJson);
      expect(dto.portraitBytes, bytes);
      expect(dto.videos, hasLength(1));
    });

    test('handles null portrait bytes', () {
      final dto = ProfileSummaryDto.fromParts(
        meJson: const <String, dynamic>{},
        portraitBytes: null,
        videos: const [],
      );

      expect(dto.portraitBytes, isNull);
      expect(dto.videos, isEmpty);
    });
  });
}
