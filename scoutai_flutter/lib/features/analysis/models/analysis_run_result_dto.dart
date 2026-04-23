class AnalysisRunResultDto {
  const AnalysisRunResultDto({required this.raw});

  final Map<String, dynamic> raw;

  factory AnalysisRunResultDto.fromJson(Map<String, dynamic> json) {
    return AnalysisRunResultDto(raw: json);
  }
}
