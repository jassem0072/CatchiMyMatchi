import 'dart:typed_data';

import '../../player/models/player.dart';

class ProfileSummary {
  const ProfileSummary({
    required this.player,
    required this.meRaw,
    required this.portraitBytes,
    required this.videos,
  });

  final Player player;
  final Map<String, dynamic> meRaw;
  final Uint8List? portraitBytes;
  final List<dynamic> videos;
}
