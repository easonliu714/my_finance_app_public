import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P4.12.2 captures and forwards transaction fingerprints', () {
    final preview = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_reconciliation_preview.dart',
    ).readAsStringSync();
    final review = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_reconciliation_review.dart',
    ).readAsStringSync();
    final enrichment = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_enrichment_service.dart',
    ).readAsStringSync();

    expect(preview, contains('transactionFingerprint: transactionFingerprint'));
    expect(review, contains('expectedTransactionFingerprint'));
    expect(enrichment, contains('expectedTransactionFingerprint: expectedFingerprint'));
  });
}
