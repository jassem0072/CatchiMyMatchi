class InvoiceDto {
  const InvoiceDto({
    required this.invoiceId,
    required this.amountEur,
    required this.claimedPlayers,
    required this.requestedAt,
    required this.expectedPaymentAt,
    required this.payoutProvider,
    required this.payoutDestinationMasked,
    required this.transactionReference,
    required this.status,
  });

  final String invoiceId;
  final double amountEur;
  final int claimedPlayers;
  final String requestedAt;
  final String expectedPaymentAt;
  final String payoutProvider;
  final String payoutDestinationMasked;
  final String transactionReference;
  final String status;

  factory InvoiceDto.fromJson(Map<String, dynamic> json) {
    return InvoiceDto(
      invoiceId: (json['invoiceId'] ?? '').toString(),
      amountEur: _toDouble(json['amountEur']),
      claimedPlayers: _toInt(json['claimedPlayers']),
      requestedAt: (json['requestedAt'] ?? '').toString(),
      expectedPaymentAt: (json['expectedPaymentAt'] ?? '').toString(),
      payoutProvider: (json['payoutProvider'] ?? 'bank_transfer').toString(),
      payoutDestinationMasked: (json['payoutDestinationMasked'] ?? '').toString(),
      transactionReference: (json['transactionReference'] ?? '').toString(),
      status: (json['status'] ?? 'requested').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'invoiceId': invoiceId,
        'amountEur': amountEur,
        'claimedPlayers': claimedPlayers,
        'requestedAt': requestedAt,
        'expectedPaymentAt': expectedPaymentAt,
        'payoutProvider': payoutProvider,
        'payoutDestinationMasked': payoutDestinationMasked,
        'transactionReference': transactionReference,
        'status': status,
      };

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
