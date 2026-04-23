import 'comparator_side.dart';

class ComparatorResult {
  const ComparatorResult({
    required this.playerA,
    required this.playerB,
  });

  final ComparatorSide playerA;
  final ComparatorSide playerB;
}
