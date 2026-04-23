class ComparatorVideoMetricsDto {
  const ComparatorVideoMetricsDto({
    required this.distanceMeters,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.sprintCount,
  });

  const ComparatorVideoMetricsDto.empty()
      : distanceMeters = 0,
        avgSpeedKmh = 0,
        maxSpeedKmh = 0,
        sprintCount = 0;

  final double distanceMeters;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final int sprintCount;

  factory ComparatorVideoMetricsDto.fromJson(Map<String, dynamic> json) {
    return ComparatorVideoMetricsDto(
      distanceMeters: _toDouble(json['distanceMeters']),
      avgSpeedKmh: _toDouble(json['avgSpeedKmh']),
      maxSpeedKmh: _toDouble(json['maxSpeedKmh']),
      sprintCount: _toInt(json['sprintCount']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'distanceMeters': distanceMeters,
      'avgSpeedKmh': avgSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'sprintCount': sprintCount,
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
