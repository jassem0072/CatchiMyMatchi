class SpeedSamplePointDto {
  const SpeedSamplePointDto({
    required this.t,
    required this.kmh,
  });

  final double t;
  final double kmh;

  factory SpeedSamplePointDto.fromJson(Map<String, dynamic> json) {
    return SpeedSamplePointDto(
      t: _toDouble(json['t']),
      kmh: _toDouble(json['kmh']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      't': t,
      'kmh': kmh,
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
