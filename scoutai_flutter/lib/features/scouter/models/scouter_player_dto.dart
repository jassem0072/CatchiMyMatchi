class ScouterPlayerDto {
  const ScouterPlayerDto({
    required this.id,
    required this.displayName,
    required this.email,
    required this.playerIdNumber,
    required this.position,
    required this.nation,
    required this.isFavorite,
    required this.hasAdminWorkflow,
  });

  final String id;
  final String displayName;
  final String email;
  final String playerIdNumber;
  final String position;
  final String nation;
  final bool isFavorite;
  final bool hasAdminWorkflow;

  factory ScouterPlayerDto.fromJson(Map<String, dynamic> json) {
    return ScouterPlayerDto(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      playerIdNumber: (json['playerIdNumber'] ?? '').toString(),
      position: ((json['position'] ?? 'CM').toString()).toUpperCase(),
      nation: (json['nation'] ?? '').toString(),
      isFavorite: _toBool(json['isFavorite']),
      hasAdminWorkflow: json['adminWorkflow'] is Map,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'email': email,
      'playerIdNumber': playerIdNumber,
      'position': position,
      'nation': nation,
      'isFavorite': isFavorite,
      'hasAdminWorkflow': hasAdminWorkflow,
    };
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value?.toString().toLowerCase().trim() ?? '';
    return s == 'true' || s == '1' || s == 'yes';
  }
}
