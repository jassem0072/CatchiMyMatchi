class PlayerDto {
  const PlayerDto({
    required this.id,
    required this.displayName,
    required this.email,
    required this.position,
    required this.nation,
  });

  final String id;
  final String displayName;
  final String email;
  final String position;
  final String nation;

  factory PlayerDto.fromJson(Map<String, dynamic> json) {
    return PlayerDto(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      position: ((json['position'] ?? 'CM').toString()).toUpperCase(),
      nation: (json['nation'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'email': email,
      'position': position,
      'nation': nation,
    };
  }
}
