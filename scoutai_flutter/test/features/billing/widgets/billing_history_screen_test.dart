import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/billing/models/invoice.dart';
import 'package:scoutai/features/billing/providers/invoice_providers.dart';
import 'package:scoutai/screens/billing_history_screen.dart';

// Minimal app wrapper that provides localizations
Widget testApp(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [],
      home: child,
    ),
  );
}

Invoice fakeInvoice({
  String id = 'INV-001',
  double amountEur = 90.0,
  int claimedPlayers = 3,
  String status = 'requested',
}) =>
    Invoice(
      id: id,
      amountEur: amountEur,
      claimedPlayers: claimedPlayers,
      requestedAt: DateTime(2025, 6, 1),
      expectedPaymentAt: DateTime(2025, 6, 4),
      payoutProvider: 'bank_transfer',
      payoutDestinationMasked: '****1234',
      transactionReference: 'REF-001',
      status: status,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Loading state ──────────────────────────────────────────────────────────
  group('BillingHistoryScreen — loading state', () {
    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // Use a Completer so we have explicit control over when the future resolves.
      final completer = Completer<List<Invoice>>();
      final override = expertInvoicesProvider.overrideWith(
        (ref) => completer.future,
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));

      // One frame — Riverpod is in AsyncLoading, body should show spinner.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Resolve the future and clean up.
      completer.complete(<Invoice>[]);
      await tester.pumpAndSettle();
    });
  });

  // ── Empty state ────────────────────────────────────────────────────────────
  group('BillingHistoryScreen — empty state', () {
    testWidgets('shows no-invoices message when list is empty', (tester) async {
      final override = expertInvoicesProvider.overrideWith(
        (ref) async => <Invoice>[],
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));

      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    });
  });

  // ── Data state ─────────────────────────────────────────────────────────────
  group('BillingHistoryScreen — data state', () {
    testWidgets('shows invoice ID in card', (tester) async {
      final override = expertInvoicesProvider.overrideWith(
        (ref) async => [fakeInvoice(id: 'INV-TEST-42')],
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('INV-TEST-42'), findsOneWidget);
    });

    testWidgets('shows EUR amount', (tester) async {
      final override = expertInvoicesProvider.overrideWith(
        (ref) async => [fakeInvoice(amountEur: 120.0)],
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('EUR 120.00'), findsOneWidget);
    });

    testWidgets('shows claimedPlayers label', (tester) async {
      final override = expertInvoicesProvider.overrideWith(
        (ref) async => [fakeInvoice(claimedPlayers: 4)],
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('4 verified player'), findsOneWidget);
    });

    testWidgets('shows Download Invoice PDF button', (tester) async {
      final override = expertInvoicesProvider.overrideWith(
        (ref) async => [fakeInvoice()],
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Download Invoice PDF'), findsOneWidget);
    });

    testWidgets('shows status badge', (tester) async {
      final override = expertInvoicesProvider.overrideWith(
        (ref) async => [fakeInvoice(status: 'paid')],
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('PAID'), findsOneWidget);
    });

    testWidgets('renders multiple invoice cards', (tester) async {
      // Give the test a large viewport so all 3 cards are visible.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final override = expertInvoicesProvider.overrideWith(
        (ref) async => [
          fakeInvoice(id: 'INV-A'),
          fakeInvoice(id: 'INV-B'),
          fakeInvoice(id: 'INV-C'),
        ],
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));
      await tester.pumpAndSettle();

      // All 3 cards must be present in the widget tree.
      expect(find.textContaining('INV-A'), findsOneWidget);
      expect(find.textContaining('INV-B'), findsOneWidget);
      expect(find.textContaining('INV-C'), findsOneWidget);
    });
  });

  // ── Error state ────────────────────────────────────────────────────────────
  group('BillingHistoryScreen — error state', () {
    testWidgets('shows error message and retry button on failure', (tester) async {
      final override = expertInvoicesProvider.overrideWith(
        (ref) async => throw Exception('Network error'),
      );

      await tester.pumpWidget(testApp(
        const BillingHistoryScreen(),
        overrides: [override],
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
