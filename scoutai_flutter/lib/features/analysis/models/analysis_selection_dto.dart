class AnalysisSelectionDto {
  const AnalysisSelectionDto({
    required this.t0,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double t0;
  final double x;
  final double y;
  final double w;
  final double h;

  factory AnalysisSelectionDto.fromJson(Map<String, dynamic> json) {
    return AnalysisSelectionDto(
      t0: _toDouble(json['t0']),
      x: _toDouble(json['x']),
      y: _toDouble(json['y']),
      w: _toDouble(json['w']),
      h: _toDouble(json['h']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      't0': t0,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
