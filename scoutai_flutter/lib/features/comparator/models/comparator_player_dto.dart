class ComparatorPlayerDto {
  const ComparatorPlayerDto({
    required this.id,
    required this.displayName,
    required this.email,
    required this.position,
    required this.nation,
    required this.playerIdNumber,
  });

  final String id;
  final String displayName;
  final String email;
  final String position;
  final String nation;
  final String playerIdNumber;

  factory ComparatorPlayerDto.fromJson(Map<String, dynamic> json) {
    return ComparatorPlayerDto(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      position: ((json['position'] ?? 'CM').toString()).toUpperCase(),
      nation: (json['nation'] ?? '').toString(),
      playerIdNumber: (json['playerIdNumber'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'email': email,
      'position': position,
      'nation': nation,
      'playerIdNumber': playerIdNumber,
    };
  }
}
