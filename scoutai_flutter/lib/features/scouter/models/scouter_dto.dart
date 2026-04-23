class ScouterDto {
  const ScouterDto({
    required this.id,
    required this.displayName,
    required this.email,
    required this.role,
    required this.nation,
    required this.subscriptionTier,
    required this.isVerified,
    required this.isPremium,
  });

  final String id;
  final String displayName;
  final String email;
  final String role;
  final String nation;
  final String subscriptionTier;
  final bool isVerified;
  final bool isPremium;

  factory ScouterDto.fromJson(Map<String, dynamic> json) {
    return ScouterDto(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'scouter').toString(),
      nation: (json['nation'] ?? '').toString(),
      subscriptionTier: (json['tier'] ?? json['subscriptionTier'] ?? json['plan'] ?? '').toString(),
      isVerified: _toBool(json['verified'] ?? json['isVerified'] ?? json['isEmailVerified']),
      isPremium: _toBool(json['isPremium'] ?? json['upgraded'] ?? json['isUpgraded']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'email': email,
      'role': role,
      'nation': nation,
      'subscriptionTier': subscriptionTier,
      'isVerified': isVerified,
      'isPremium': isPremium,
    };
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value?.toString().toLowerCase().trim() ?? '';
    return s == 'true' || s == '1' || s == 'yes';
  }
}
