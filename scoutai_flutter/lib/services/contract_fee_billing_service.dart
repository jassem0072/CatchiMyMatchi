import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'pdf_download_helper.dart';

class ContractFeeInvoice {
  ContractFeeInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.createdAtIso,
    required this.contractReference,
    required this.currency,
    required this.contractAmount,
    required this.percentage,
    required this.feeAmount,
    required this.payerName,
    required this.payerEmail,
    this.invoiceFilePath,
  });

  final String id;
  final String invoiceNumber;
  final String createdAtIso;
  final String contractReference;
  final String currency;
  final double contractAmount;
  final double percentage;
  final double feeAmount;
  final String payerName;
  final String payerEmail;
  final String? invoiceFilePath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceNumber': invoiceNumber,
        'createdAtIso': createdAtIso,
        'contractReference': contractReference,
        'currency': currency,
        'contractAmount': contractAmount,
        'percentage': percentage,
        'feeAmount': feeAmount,
        'payerName': payerName,
        'payerEmail': payerEmail,
        'invoiceFilePath': invoiceFilePath,
      };

  static ContractFeeInvoice fromJson(Map<String, dynamic> json) {
    return ContractFeeInvoice(
      id: (json['id'] ?? '').toString(),
      invoiceNumber: (json['invoiceNumber'] ?? '').toString(),
      createdAtIso: (json['createdAtIso'] ?? '').toString(),
      contractReference: (json['contractReference'] ?? '').toString(),
      currency: (json['currency'] ?? 'EUR').toString(),
      contractAmount: (json['contractAmount'] is num) ? (json['contractAmount'] as num).toDouble() : 0,
      percentage: (json['percentage'] is num) ? (json['percentage'] as num).toDouble() : 3,
      feeAmount: (json['feeAmount'] is num) ? (json['feeAmount'] as num).toDouble() : 0,
      payerName: (json['payerName'] ?? '').toString(),
      payerEmail: (json['payerEmail'] ?? '').toString(),
      invoiceFilePath: (json['invoiceFilePath'] ?? '').toString().trim().isEmpty ? null : (json['invoiceFilePath'] as String),
    );
  }
}

class ContractFeePaymentResult {
  ContractFeePaymentResult({
    required this.invoice,
    required this.invoiceFileName,
    required this.invoiceBytes,
  });

  final ContractFeeInvoice invoice;
  final String invoiceFileName;
  final Uint8List invoiceBytes;
}

class ContractFeeBillingService {
  static const String _storageKey = 'scoutai_contract_fee_invoices_v1';

  static Future<List<ContractFeeInvoice>> getInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return <ContractFeeInvoice>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ContractFeeInvoice>[];
      final items = decoded
          .whereType<Map>()
          .map((e) => ContractFeeInvoice.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      items.sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));
      return items;
    } catch (_) {
      return <ContractFeeInvoice>[];
    }
  }

  static Future<ContractFeePaymentResult> createOptionalPayment({
    required String payerName,
    required String payerEmail,
    required String contractReference,
    required String currency,
    required double contractAmount,
    required double percentage,
  }) async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}';
    final cleanCurrency = currency.trim().isEmpty ? 'EUR' : currency.trim().toUpperCase();
    final feeAmount = contractAmount * (percentage / 100);
    final invoiceNumber = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(7)}';

    final invoice = ContractFeeInvoice(
      id: id,
      invoiceNumber: invoiceNumber,
      createdAtIso: now.toIso8601String(),
      contractReference: contractReference.trim().isEmpty ? 'Contract' : contractReference.trim(),
      currency: cleanCurrency,
      contractAmount: contractAmount,
      percentage: percentage,
      feeAmount: feeAmount,
      payerName: payerName.trim().isEmpty ? 'Scouter' : payerName.trim(),
      payerEmail: payerEmail.trim(),
    );

    final bytes = await _buildInvoicePdf(invoice);
    final safeRef = invoice.contractReference.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final fileName = 'ScoutAI_Invoice_${invoice.invoiceNumber}_$safeRef.pdf';
    String? filePath;

    final downloadedOnWeb = await triggerPdfDownload(bytes, fileName);
    if (!downloadedOnWeb && !kIsWeb) {
      final directory = await getApplicationDocumentsDirectory();
      final invoicesDir = Directory('${directory.path}${Platform.pathSeparator}invoices');
      if (!invoicesDir.existsSync()) {
        invoicesDir.createSync(recursive: true);
      }
      final f = File('${invoicesDir.path}${Platform.pathSeparator}$fileName');
      await f.writeAsBytes(bytes, flush: true);
      filePath = f.path;
    }

    final stored = ContractFeeInvoice(
      id: invoice.id,
      invoiceNumber: invoice.invoiceNumber,
      createdAtIso: invoice.createdAtIso,
      contractReference: invoice.contractReference,
      currency: invoice.currency,
      contractAmount: invoice.contractAmount,
      percentage: invoice.percentage,
      feeAmount: invoice.feeAmount,
      payerName: invoice.payerName,
      payerEmail: invoice.payerEmail,
      invoiceFilePath: filePath,
    );

    await _appendInvoice(stored);

    return ContractFeePaymentResult(
      invoice: stored,
      invoiceFileName: fileName,
      invoiceBytes: bytes,
    );
  }

  static Future<void> _appendInvoice(ContractFeeInvoice invoice) async {
    final existing = await getInvoices();
    final next = <ContractFeeInvoice>[invoice, ...existing];
    final prefs = await SharedPreferences.getInstance();
    final jsonList = next.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  static Future<Uint8List> _buildInvoicePdf(ContractFeeInvoice invoice) async {
    final doc = pw.Document();
    final createdAt = DateTime.tryParse(invoice.createdAtIso) ?? DateTime.now();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blueGrey900,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('SCOUTAI INVOICE', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 18)),
                    pw.SizedBox(height: 4),
                    pw.Text('Optional contract percentage payment', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: const ['Field', 'Value'],
                data: [
                  ['Invoice Number', invoice.invoiceNumber],
                  ['Date', '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}'],
                  ['Payer Name', invoice.payerName],
                  ['Payer Email', invoice.payerEmail.isEmpty ? '-' : invoice.payerEmail],
                  ['Contract Reference', invoice.contractReference],
                  ['Contract Amount', '${invoice.currency} ${invoice.contractAmount.toStringAsFixed(2)}'],
                  ['Agency Percentage', '${invoice.percentage.toStringAsFixed(2)}%'],
                  ['Amount Paid', '${invoice.currency} ${invoice.feeAmount.toStringAsFixed(2)}'],
                  ['Payment Type', 'Card (recorded in app)'],
                  ['Status', 'Paid'],
                ],
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'This document confirms an optional platform percentage payment related to the contract above.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
