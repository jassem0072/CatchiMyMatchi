class PlayerVideo {
  const PlayerVideo({
    required this.id,
    required this.originalName,
    this.createdAt,
    this.lastAnalysis,
  });

  final String id;
  final String originalName;
  final DateTime? createdAt;
  final PlayerVideoAnalysis? lastAnalysis;
}

class PlayerVideoAnalysis {
  const PlayerVideoAnalysis({
    required this.distanceKm,
    required this.maxSpeedKmh,
    required this.sprints,
  });

  final double distanceKm;
  final double maxSpeedKmh;
  final int sprints;
}
