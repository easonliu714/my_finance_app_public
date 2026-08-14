import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft.dart';

void main() {
  test('ManualInvoiceDraft map roundtrip preserves invoice time', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'ab12345678',
      invoiceDate: DateTime(2026, 6, 9, 14, 35),
      sellerName: '測試便利商店',
      totalAmount: 120,
      taxAmount: 6,
      note: '早餐',
      status: ManualInvoiceDraftStatus.readyToReview,
      createdAt: DateTime.utc(2026, 6, 9, 1, 0),
      updatedAt: DateTime.utc(2026, 6, 9, 2, 0),
    );

    final map = draft.toMap();
    final restored = ManualInvoiceDraft.fromMap(map);

    expect(map['invoice_date'], '2026-06-09T14:35:00.000');
    expect(restored.invoiceDate.year, 2026);
    expect(restored.invoiceDate.month, 6);
    expect(restored.invoiceDate.day, 9);
    expect(restored.invoiceDate.hour, 14);
    expect(restored.invoiceDate.minute, 35);
    expect(restored.duplicateKey, 'AB12345678|2026-06-09|120|測試便利商店');
  });

  test('ManualInvoiceDraft remains compatible with date-only stored values', () {
    final restored = ManualInvoiceDraft.fromMap(const <String, Object?>{
      'id': 'draft-legacy',
      'invoice_number': 'AB12345678',
      'invoice_date': '2026-06-09',
      'seller_name': '測試便利商店',
      'total_amount': 120,
      'status': 'readyToReview',
    });

    expect(restored.invoiceDate, DateTime(2026, 6, 9));
    expect(restored.duplicateKey, 'AB12345678|2026-06-09|120|測試便利商店');
  });
}
