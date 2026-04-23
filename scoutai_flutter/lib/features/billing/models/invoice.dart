class Invoice {
  const Invoice({
    required this.id,
    required this.amountEur,
    required this.claimedPlayers,
    required this.requestedAt,
    required this.expectedPaymentAt,
    required this.payoutProvider,
    required this.payoutDestinationMasked,
    required this.transactionReference,
    required this.status,
  });

  final String id;
  final double amountEur;
  final int claimedPlayers;
  final DateTime requestedAt;
  final DateTime expectedPaymentAt;
  final String payoutProvider;
  final String payoutDestinationMasked;
  final String transactionReference;
  final String status; // 'requested' | 'processing' | 'paid'

  bool get isPaid => status == 'paid';
  bool get isProcessing => status == 'processing';
}
