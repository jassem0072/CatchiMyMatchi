import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:scoutai/core/network/api_client.dart';
import 'package:scoutai/features/billing/services/invoice_service.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const baseUrl = 'https://api.test.com';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => setupMockSharedPreferences());
  tearDown(() => tearDownMockSharedPreferences());

  Map<String, dynamic> invoiceJson({
    String id = 'INV-001',
    double amount = 90.0,
    int players = 3,
    String status = 'requested',
  }) =>
      {
        'invoiceId': id,
        'amountEur': amount,
        'claimedPlayers': players,
        'requestedAt': '2025-06-01T08:00:00.000Z',
        'expectedPaymentAt': '2025-06-04T08:00:00.000Z',
        'payoutProvider': 'bank_transfer',
        'payoutDestinationMasked': '****1234',
        'transactionReference': 'REF-001',
        'status': status,
      };

  group('InvoiceService.getInvoices', () {
    test('returns parsed invoice list', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/admin/expert/invoices') {
          return http.Response(
            jsonEncode([
              invoiceJson(id: 'INV-001', amount: 90.0, players: 3),
              invoiceJson(id: 'INV-002', amount: 30.0, players: 1, status: 'paid'),
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = InvoiceService(ApiClient(client: mock, baseUrl: baseUrl));
      final invoices = await service.getInvoices();

      expect(invoices, hasLength(2));
      expect(invoices[0].id, 'INV-001');
      expect(invoices[0].amountEur, 90.0);
      expect(invoices[0].claimedPlayers, 3);
      expect(invoices[0].isPaid, isFalse);
      expect(invoices[1].id, 'INV-002');
      expect(invoices[1].isPaid, isTrue);
    });

    test('returns empty list for non-list response', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode({'error': 'bad'}), 200);
      });

      final service = InvoiceService(ApiClient(client: mock, baseUrl: baseUrl));
      final invoices = await service.getInvoices();

      expect(invoices, isEmpty);
    });

    test('skips non-map entries in list', () async {
      final mock = http_testing.MockClient((request) async {
        if (request.url.path == '/admin/expert/invoices') {
          return http.Response(
            jsonEncode([
              invoiceJson(id: 'INV-VALID'),
              'invalid-entry',
              42,
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = InvoiceService(ApiClient(client: mock, baseUrl: baseUrl));
      final invoices = await service.getInvoices();

      expect(invoices, hasLength(1));
      expect(invoices[0].id, 'INV-VALID');
    });

    test('throws on 401 unauthorized', () async {
      final mock = http_testing.MockClient((request) async {
        return http.Response(jsonEncode({'message': 'Unauthorized'}), 401);
      });

      final service = InvoiceService(ApiClient(client: mock, baseUrl: baseUrl));
      expect(() => service.getInvoices(), throwsA(isA<Exception>()));
    });
  });
}
