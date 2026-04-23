import '../../../core/network/api_client.dart';
import '../models/invoice.dart';
import '../models/invoice_dto.dart';
import '../models/invoice_mapper.dart';

class InvoiceService {
  const InvoiceService(this._apiClient);

  final ApiClient _apiClient;

  /// Returns the expert's payout invoices from the backend.
  Future<List<Invoice>> getInvoices() async {
    final data = await _apiClient.get('/admin/expert/invoices');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => InvoiceMapper.toEntity(
              InvoiceDto.fromJson(Map<String, dynamic>.from(e)),
            ))
        .toList();
  }
}
