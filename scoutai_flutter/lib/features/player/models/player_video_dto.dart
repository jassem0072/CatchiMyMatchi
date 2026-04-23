class PlayerVideoDto {
  const PlayerVideoDto({
    required this.id,
    required this.originalName,
    this.createdAt,
    this.lastAnalysis,
  });

  final String id;
  final String originalName;
  final DateTime? createdAt;
  final PlayerVideoAnalysisDto? lastAnalysis;

  factory PlayerVideoDto.fromJson(Map<String, dynamic> json) {
    final rawLast = json['lastAnalysis'];
    return PlayerVideoDto(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      originalName: (json['originalName'] ?? json['filename'] ?? 'Video').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      lastAnalysis: rawLast is Map<String, dynamic>
          ? PlayerVideoAnalysisDto.fromJson(rawLast)
          : (rawLast is Map ? PlayerVideoAnalysisDto.fromJson(Map<String, dynamic>.from(rawLast)) : null),
    );
  }
}

class PlayerVideoAnalysisDto {
  const PlayerVideoAnalysisDto({
    required this.distanceKm,
    required this.maxSpeedKmh,
    required this.sprints,
  });

  final double distanceKm;
  final double maxSpeedKmh;
  final int sprints;

  factory PlayerVideoAnalysisDto.fromJson(Map<String, dynamic> json) {
    final rawMetrics = json['metrics'];
    final metrics = rawMetrics is Map<String, dynamic>
        ? rawMetrics
        : (rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : const <String, dynamic>{});

    return PlayerVideoAnalysisDto(
      distanceKm: _toDouble(
        json['distanceKm'] ?? json['distance_km'] ?? json['distance'] ?? metrics['distanceKm'],
      ),
      maxSpeedKmh: _toDouble(
        json['maxSpeedKmh'] ?? json['max_speed_kmh'] ?? json['maxSpeed'] ?? metrics['maxSpeedKmh'],
      ),
      sprints: _toInt(
        json['sprints'] ?? json['sprintCount'] ?? metrics['sprints'],
      ),
    );
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
