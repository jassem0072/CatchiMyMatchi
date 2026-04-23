import 'comparator_video_metrics.dart';

class ComparatorVideoEntry {
  const ComparatorVideoEntry({
    required this.originalName,
    required this.metrics,
  });

  final String originalName;
  final ComparatorVideoMetrics metrics;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'originalName': originalName,
      'metrics': metrics.toJson(),
    };
  }
}
