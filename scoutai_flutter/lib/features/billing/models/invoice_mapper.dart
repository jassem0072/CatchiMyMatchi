import 'invoice.dart';
import 'invoice_dto.dart';

class InvoiceMapper {
  const InvoiceMapper._();

  static Invoice toEntity(InvoiceDto dto) {
    return Invoice(
      id: dto.invoiceId,
      amountEur: dto.amountEur,
      claimedPlayers: dto.claimedPlayers,
      requestedAt: _parseDate(dto.requestedAt),
      expectedPaymentAt: _parseDate(dto.expectedPaymentAt),
      payoutProvider: dto.payoutProvider,
      payoutDestinationMasked: dto.payoutDestinationMasked,
      transactionReference: dto.transactionReference,
      status: dto.status,
    );
  }

  static DateTime _parseDate(String iso) {
    return DateTime.tryParse(iso) ?? DateTime.now();
  }
}
