class ComparatorAggregatedMetricsDto {
  const ComparatorAggregatedMetricsDto({
    required this.totalDistanceMeters,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.totalSprints,
    required this.totalAccelPeaks,
    required this.analyzedVideos,
  });

  const ComparatorAggregatedMetricsDto.empty()
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

  factory ComparatorAggregatedMetricsDto.fromJson(Map<String, dynamic> json) {
    return ComparatorAggregatedMetricsDto(
      totalDistanceMeters: _toDouble(json['totalDistanceMeters']),
      avgSpeedKmh: _toDouble(json['avgSpeedKmh']),
      maxSpeedKmh: _toDouble(json['maxSpeedKmh']),
      totalSprints: _toDouble(json['totalSprints']),
      totalAccelPeaks: _toDouble(json['totalAccelPeaks']),
      analyzedVideos: _toDouble(json['analyzedVideos']),
    );
  }

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

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
