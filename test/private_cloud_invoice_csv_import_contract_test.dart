import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LAB exposes accountless reconciliation and unmatched review', () {
    final lab = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_page.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_import_page.dart',
    ).readAsStringSync();

    expect(lab, contains('財政部 CSV 手動匯入驗證'));
    expect(lab, contains('PrivateCloudInvoiceCsvImportPage'));
    expect(page, contains('選擇財政部 CSV 並比對'));
    expect(page, contains('完成本次覆核'));
    expect(page, contains('我確認將發票資訊補充到選定的既有交易'));
    expect(page, contains('未比對發票：批次選帳戶'));
    expect(page, contains('套用帳戶到選取發票'));
    expect(page, contains('暫緩'));
    expect(page, contains('未指定帳戶'));
    expect(page, contains('本次已完成歸戶的發票建立非正式草稿'));
    expect(page, contains('查看完整品項'));
    expect(page, contains('正式交易筆數：未變更'));
    expect(page, isNot(contains('草稿歸屬帳戶')));
    expect(page, isNot(contains('建立選取的非正式草稿')));
  });

  test('CSV import service builds accountless reconciliation', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_import_service.dart',
    ).readAsStringSync();

    expect(source, contains('buildReconciliationPreview'));
    expect(source, contains('TransactionType.expense.name'));
    expect(source, contains('PrivateCloudInvoiceCsvReconciliationPreview'));
    expect(source, isNot(contains('replaceExisting')));
  });

  test('enrichment service writes metadata only after confirmation', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_enrichment_service.dart',
    ).readAsStringSync();

    expect(source, contains('ENRICHMENT_CONFIRMATION_REQUIRED'));
    expect(source, contains('CloudInvoiceReconciliationOutcome.enrichExisting'));
    expect(source, contains('expectedTransactionFingerprint'));
    expect(source, contains('merchantProposalConfirmed: false'));
    expect(source, isNot(contains('replaceExisting')));
    expect(source, isNot(contains('createNewDraft')));
  });

  test('unmatched review explicitly defers missing-account invoices', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_unmatched_review.dart',
    ).readAsStringSync();

    expect(source, contains('deferSelectedWithoutAccount'));
    expect(source, contains('canDeferMissingAccounts'));
    expect(source, contains('missingAccountCount == 0'));
    expect(source, contains('selectedCount > 0 && missingAccountCount == 0'));
  });

  test('unmatched draft service groups selected invoices by account', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_unmatched_draft_service.dart',
    ).readAsStringSync();

    expect(source, contains('selectedInvoiceIdsByAccount'));
    expect(source, contains('importPort.importDrafts'));
    expect(source, contains('transactionCountUnchanged'));
    expect(source, isNot(contains('replaceExisting')));
    expect(source, isNot(contains('enrichExisting')));
  });
}
