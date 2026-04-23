class ComparatorVideoMetrics {
  const ComparatorVideoMetrics({
    required this.distanceMeters,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.sprintCount,
  });

  const ComparatorVideoMetrics.empty()
      : distanceMeters = 0,
        avgSpeedKmh = 0,
        maxSpeedKmh = 0,
        sprintCount = 0;

  final double distanceMeters;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final int sprintCount;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'distanceMeters': distanceMeters,
      'avgSpeedKmh': avgSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'sprintCount': sprintCount,
    };
  }
}
