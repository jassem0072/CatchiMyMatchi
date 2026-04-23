import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/billing/models/invoice_dto.dart';
import 'package:scoutai/features/billing/models/invoice_mapper.dart';

void main() {
  group('InvoiceMapper.toEntity', () {
    InvoiceDto dto({
      String invoiceId = 'INV-001',
      double amountEur = 90.0,
      int claimedPlayers = 3,
      String requestedAt = '2025-06-01T08:00:00.000Z',
      String expectedPaymentAt = '2025-06-04T08:00:00.000Z',
      String payoutProvider = 'bank_transfer',
      String payoutDestinationMasked = '****9999',
      String transactionReference = 'REF-999',
      String status = 'requested',
    }) =>
        InvoiceDto(
          invoiceId: invoiceId,
          amountEur: amountEur,
          claimedPlayers: claimedPlayers,
          requestedAt: requestedAt,
          expectedPaymentAt: expectedPaymentAt,
          payoutProvider: payoutProvider,
          payoutDestinationMasked: payoutDestinationMasked,
          transactionReference: transactionReference,
          status: status,
        );

    test('maps invoiceId to entity id', () {
      final entity = InvoiceMapper.toEntity(dto(invoiceId: 'INV-ABC'));
      expect(entity.id, 'INV-ABC');
    });

    test('maps amountEur correctly', () {
      final entity = InvoiceMapper.toEntity(dto(amountEur: 120.0));
      expect(entity.amountEur, 120.0);
    });

    test('maps claimedPlayers correctly', () {
      final entity = InvoiceMapper.toEntity(dto(claimedPlayers: 4));
      expect(entity.claimedPlayers, 4);
    });

    test('parses requestedAt ISO string to DateTime', () {
      final entity = InvoiceMapper.toEntity(
        dto(requestedAt: '2025-06-01T08:00:00.000Z'),
      );
      expect(entity.requestedAt.year, 2025);
      expect(entity.requestedAt.month, 6);
      expect(entity.requestedAt.day, 1);
    });

    test('parses expectedPaymentAt ISO string to DateTime', () {
      final entity = InvoiceMapper.toEntity(
        dto(expectedPaymentAt: '2025-06-04T00:00:00.000Z'),
      );
      expect(entity.expectedPaymentAt.year, 2025);
      expect(entity.expectedPaymentAt.month, 6);
      expect(entity.expectedPaymentAt.day, 4);
    });

    test('falls back to DateTime.now() for invalid date string', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final entity = InvoiceMapper.toEntity(dto(requestedAt: 'not-a-date'));
      expect(entity.requestedAt.isAfter(before), isTrue);
    });

    test('isPaid returns true only for paid status', () {
      expect(InvoiceMapper.toEntity(dto(status: 'paid')).isPaid, isTrue);
      expect(InvoiceMapper.toEntity(dto(status: 'requested')).isPaid, isFalse);
    });

    test('isProcessing returns true only for processing status', () {
      expect(
          InvoiceMapper.toEntity(dto(status: 'processing')).isProcessing, isTrue);
      expect(
          InvoiceMapper.toEntity(dto(status: 'paid')).isProcessing, isFalse);
    });
  });
}
