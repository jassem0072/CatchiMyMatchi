import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/invoice.dart';
import '../services/invoice_service.dart';

final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return InvoiceService(apiClient);
});

final expertInvoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final service = ref.watch(invoiceServiceProvider);
  return service.getInvoices();
});
