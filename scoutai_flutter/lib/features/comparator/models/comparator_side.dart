import 'comparator_aggregated_metrics.dart';
import 'comparator_video_entry.dart';

class ComparatorSide {
  const ComparatorSide({
    required this.aggregated,
    required this.videos,
  });

  final ComparatorAggregatedMetrics aggregated;
  final List<ComparatorVideoEntry> videos;
}
