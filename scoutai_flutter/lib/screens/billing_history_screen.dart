import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../features/billing/models/invoice.dart';
import '../features/billing/providers/invoice_providers.dart';
import '../services/pdf_download_helper.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

// ─── Screen ──────────────────────────────────────────────────────────────────

class BillingHistoryScreen extends ConsumerWidget {
  const BillingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final invoicesAsync = ref.watch(expertInvoicesProvider);

    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.billingHistory),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(expertInvoicesProvider),
          ),
        ],
      ),
      body: invoicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppColors.danger, size: 36),
                const SizedBox(height: 10),
                Text(
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(expertInvoicesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (invoices) => invoices.isEmpty
            ? _EmptyState(s: s)
            : _InvoiceList(invoices: invoices),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.s});
  final S s;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 64, color: AppColors.txMuted(context)),
            const SizedBox(height: 16),
            Text(
              s.noBillingHistory,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'No payout invoices yet. Submit your billing details in the web panel to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.txMuted(context), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Invoice list ─────────────────────────────────────────────────────────────

class _InvoiceList extends StatelessWidget {
  const _InvoiceList({required this.invoices});
  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: invoices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _InvoiceCard(invoice: invoices[index]),
    );
  }
}

// ─── Invoice card ─────────────────────────────────────────────────────────────

class _InvoiceCard extends StatefulWidget {
  const _InvoiceCard({required this.invoice});
  final Invoice invoice;

  @override
  State<_InvoiceCard> createState() => _InvoiceCardState();
}

class _InvoiceCardState extends State<_InvoiceCard> {
  bool _downloading = false;

  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Color _statusColor(BuildContext ctx) {
    if (widget.invoice.isPaid) return AppColors.success;
    if (widget.invoice.isProcessing) return Colors.orange;
    return AppColors.primary;
  }

  Future<void> _downloadPdf() async {
    setState(() => _downloading = true);
    try {
      final bytes = await _buildInvoicePdf(widget.invoice);
      final fileName =
          'ScoutAI_Invoice_${widget.invoice.id}.pdf';
      final downloaded = await triggerPdfDownload(bytes, fileName);
      if (!downloaded && !kIsWeb) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF saved to device')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  inv.id,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(context).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor(context).withOpacity(0.4)),
                ),
                child: Text(
                  inv.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _statusColor(context),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Amount ──────────────────────────────────────────────
          Text(
            'EUR ${inv.amountEur.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text(
            '${inv.claimedPlayers} verified player${inv.claimedPlayers != 1 ? 's' : ''} @ EUR 30 each',
            style: TextStyle(color: AppColors.txMuted(context), fontSize: 12),
          ),
          const SizedBox(height: 12),

          // ── Details ─────────────────────────────────────────────
          _DetailRow(label: 'Requested', value: _fmtDate(inv.requestedAt)),
          _DetailRow(label: 'Expected payment', value: _fmtDate(inv.expectedPaymentAt)),
          _DetailRow(
            label: 'Method',
            value: inv.payoutProvider.replaceAll('_', ' ').toUpperCase(),
          ),
          _DetailRow(label: 'Destination', value: inv.payoutDestinationMasked),
          const SizedBox(height: 14),

          // ── Download button ─────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _downloading ? null : _downloadPdf,
              icon: _downloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_downloading ? 'Generating PDF…' : 'Download Invoice PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail row helper ────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    color: AppColors.txMuted(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── PDF builder ─────────────────────────────────────────────────────────────

Future<Uint8List> _buildInvoicePdf(Invoice invoice) async {
  final doc = pw.Document();

  String fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Header band ────────────────────────────────────────
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF121B2B),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(children: [
                        pw.Text('SCOUT',
                            style: pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text('AI',
                            style: pw.TextStyle(
                                color: const PdfColor.fromInt(0xFFB7F408),
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold)),
                      ]),
                      pw.SizedBox(height: 4),
                      pw.Text('Expert Payout Invoice',
                          style: const pw.TextStyle(
                              color: PdfColors.blueGrey200, fontSize: 11)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(invoice.id,
                          style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Invoice ID',
                          style: const pw.TextStyle(
                              color: PdfColors.blueGrey200, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),

            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(36, 28, 36, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // ── Status pill ────────────────────────────────────
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: pw.BoxDecoration(
                      color: invoice.isPaid
                          ? const PdfColor.fromInt(0xFF32D583)
                          : invoice.isProcessing
                              ? const PdfColor.fromInt(0xFFFDB022)
                              : const PdfColor.fromInt(0xFF1D63FF),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
                    ),
                    child: pw.Text(
                      invoice.status.toUpperCase(),
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold),
                    ),
                  ),

                  pw.SizedBox(height: 20),

                  // ── Amount hero ─────────────────────────────────────
                  pw.Text(
                    'EUR ${invoice.amountEur.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                        fontSize: 34, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${invoice.claimedPlayers} verified player${invoice.claimedPlayers != 1 ? 's' : ''} × EUR 30.00 each',
                    style: const pw.TextStyle(
                        color: PdfColors.blueGrey400, fontSize: 12),
                  ),

                  pw.SizedBox(height: 24),
                  pw.Divider(color: PdfColors.blueGrey100),
                  pw.SizedBox(height: 20),

                  // ── Details table ───────────────────────────────────
                  pw.TableHelper.fromTextArray(
                    headers: const ['Field', 'Value'],
                    data: [
                      ['Invoice ID', invoice.id],
                      ['Requested', fmt(invoice.requestedAt)],
                      ['Expected Payment', fmt(invoice.expectedPaymentAt)],
                      ['Payout Method', invoice.payoutProvider.replaceAll('_', ' ').toUpperCase()],
                      ['Destination', invoice.payoutDestinationMasked],
                      ['Reference', invoice.transactionReference],
                      ['Claimed Players', '${invoice.claimedPlayers}'],
                      ['Status', invoice.status.toUpperCase()],
                    ],
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFEFF3F8),
                    ),
                    headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    oddRowDecoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFF7F9FC),
                    ),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(180),
                      1: const pw.FlexColumnWidth(),
                    },
                  ),

                  pw.SizedBox(height: 24),
                  pw.Divider(color: PdfColors.blueGrey100),
                  pw.SizedBox(height: 16),

                  // ── Footer note ─────────────────────────────────────
                  pw.Text(
                    'This document confirms your payout request has been submitted to ScoutAI.',
                    style: const pw.TextStyle(
                        color: PdfColors.blueGrey400, fontSize: 9),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Payment will be processed within 3 business days to the destination listed above.',
                    style: const pw.TextStyle(
                        color: PdfColors.blueGrey400, fontSize: 9),
                  ),
                ],
              ),
            ),

            pw.Spacer(),

            // ── Bottom accent bar ───────────────────────────────────
            pw.Container(
              width: double.infinity,
              height: 6,
              color: const PdfColor.fromInt(0xFF1D63FF),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}
