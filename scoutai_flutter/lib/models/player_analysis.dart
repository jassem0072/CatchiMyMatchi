class PlayerAnalysis {
  const PlayerAnalysis({
    required this.id,
    required this.playerName,
    required this.playerNumber,
    required this.matchName,
    required this.distanceKm,
    required this.maxSpeedKmh,
    required this.sprints,
    required this.status,
    this.progress,
  });

  final String id;
  final String playerName;
  final int playerNumber;
  final String matchName;
  final double distanceKm;
  final double maxSpeedKmh;
  final int sprints;
  final AnalysisStatus status;
  final double? progress;
}

enum AnalysisStatus { done, processing }
