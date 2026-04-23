import 'dart:typed_data';

import '../../player/models/player_dto.dart';

class ProfileSummaryDto {
  const ProfileSummaryDto({
    required this.playerDto,
    required this.meRaw,
    required this.portraitBytes,
    required this.videos,
  });

  final PlayerDto playerDto;
  final Map<String, dynamic> meRaw;
  final Uint8List? portraitBytes;
  final List<dynamic> videos;

  /// Constructs from raw `/me` JSON, portrait bytes, and video list.
  factory ProfileSummaryDto.fromParts({
    required Map<String, dynamic> meJson,
    required Uint8List? portraitBytes,
    required List<dynamic> videos,
  }) {
    return ProfileSummaryDto(
      playerDto: PlayerDto.fromJson(meJson),
      meRaw: meJson,
      portraitBytes: portraitBytes,
      videos: videos,
    );
  }
}
