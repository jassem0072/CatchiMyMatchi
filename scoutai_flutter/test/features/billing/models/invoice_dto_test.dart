import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/billing/models/invoice_dto.dart';

void main() {
  group('InvoiceDto.fromJson', () {
    test('parses complete JSON correctly', () {
      final dto = InvoiceDto.fromJson({
        'invoiceId': 'INV-EXP-123',
        'amountEur': 90.0,
        'claimedPlayers': 3,
        'requestedAt': '2025-01-15T10:00:00.000Z',
        'expectedPaymentAt': '2025-01-18T10:00:00.000Z',
        'payoutProvider': 'bank_transfer',
        'payoutDestinationMasked': '****1234',
        'transactionReference': 'REF-001',
        'status': 'requested',
      });

      expect(dto.invoiceId, 'INV-EXP-123');
      expect(dto.amountEur, 90.0);
      expect(dto.claimedPlayers, 3);
      expect(dto.requestedAt, '2025-01-15T10:00:00.000Z');
      expect(dto.payoutProvider, 'bank_transfer');
      expect(dto.payoutDestinationMasked, '****1234');
      expect(dto.transactionReference, 'REF-001');
      expect(dto.status, 'requested');
    });

    test('defaults to zero for missing numeric fields', () {
      final dto = InvoiceDto.fromJson(const {});
      expect(dto.amountEur, 0.0);
      expect(dto.claimedPlayers, 0);
    });

    test('defaults status to requested when missing', () {
      final dto = InvoiceDto.fromJson(const {});
      expect(dto.status, 'requested');
    });

    test('defaults payoutProvider to bank_transfer', () {
      final dto = InvoiceDto.fromJson(const {});
      expect(dto.payoutProvider, 'bank_transfer');
    });

    test('parses string numeric amountEur', () {
      final dto = InvoiceDto.fromJson({'amountEur': '60'});
      expect(dto.amountEur, 60.0);
    });

    test('parses string claimedPlayers', () {
      final dto = InvoiceDto.fromJson({'claimedPlayers': '2'});
      expect(dto.claimedPlayers, 2);
    });

    test('handles null fields gracefully', () {
      final dto = InvoiceDto.fromJson({
        'invoiceId': null,
        'amountEur': null,
        'status': null,
      });
      expect(dto.invoiceId, '');
      expect(dto.amountEur, 0.0);
      expect(dto.status, 'requested');
    });
  });

  group('InvoiceDto.toJson', () {
    test('serializes all fields', () {
      const dto = InvoiceDto(
        invoiceId: 'INV-1',
        amountEur: 30.0,
        claimedPlayers: 1,
        requestedAt: '2025-01-01T00:00:00Z',
        expectedPaymentAt: '2025-01-04T00:00:00Z',
        payoutProvider: 'paypal',
        payoutDestinationMasked: 'user@example.com',
        transactionReference: 'TXN-001',
        status: 'paid',
      );

      final json = dto.toJson();
      expect(json['invoiceId'], 'INV-1');
      expect(json['amountEur'], 30.0);
      expect(json['claimedPlayers'], 1);
      expect(json['payoutProvider'], 'paypal');
      expect(json['status'], 'paid');
    });
  });
}
