class ScouterPlayer {
  const ScouterPlayer({
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
}
