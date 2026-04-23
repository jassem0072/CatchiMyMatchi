class ComparatorAggregatedMetrics {
  const ComparatorAggregatedMetrics({
    required this.totalDistanceMeters,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.totalSprints,
    required this.totalAccelPeaks,
    required this.analyzedVideos,
  });

  const ComparatorAggregatedMetrics.empty()
      : totalDistanceMeters = 0,
        avgSpeedKmh = 0,
        maxSpeedKmh = 0,
        totalSprints = 0,
        totalAccelPeaks = 0,
        analyzedVideos = 0;

  final double totalDistanceMeters;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double totalSprints;
  final double totalAccelPeaks;
  final double analyzedVideos;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'totalDistanceMeters': totalDistanceMeters,
      'avgSpeedKmh': avgSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'totalSprints': totalSprints,
      'totalAccelPeaks': totalAccelPeaks,
      'analyzedVideos': analyzedVideos,
    };
  }
}
