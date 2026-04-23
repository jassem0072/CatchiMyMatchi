class Scouter {
  const Scouter({
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
}
