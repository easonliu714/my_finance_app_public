import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_staging_adapter.dart';
import 'package:my_finance_app/features/invoice/invoice_import_staging.dart';

void main() {
  test('pending cloud candidate becomes pending external-source staging item', () {
    const adapter = CloudInvoiceStagingAdapter();

    final item = adapter.toStagingItem(candidate: _candidate(), id: 'staging-1');

    expect(item.id, 'staging-1');
    expect(item.source, InvoiceImportStagingSource.externalSource);
    expect(item.status, InvoiceImportStagingStatus.pending);
    expect(item.invoiceNumber, 'AB12345678');
    expect(item.sellerName, '測試便利商店');
    expect(item.totalAmount, 120);
    expect(item.note, contains('雲端發票 mock 匯入候選'));
  });

  test('partial pending candidate uses fallback seller name and warning note', () {
    const adapter = CloudInvoiceStagingAdapter();

    final item = adapter.toStagingItem(
      candidate: _candidate(
        sellerName: '',
        warnings: const <CloudInvoiceCandidateWarning>[CloudInvoiceCandidateWarning.missingSellerName],
      ),
      id: 'staging-1',
    );

    expect(item.sellerName, '未命名雲端發票商家');
    expect(item.note, contains('需人工補齊'));
  });

  test('duplicate cloud candidate becomes duplicate staging item without overwrite', () {
    const adapter = CloudInvoiceStagingAdapter();

    final item = adapter.toStagingItem(
      candidate: _candidate(status: CloudInvoiceCandidateStatus.duplicate),
      id: 'staging-duplicate',
    );

    expect(item.status, InvoiceImportStagingStatus.duplicate);
    expect(item.note, contains('疑似重複'));
    expect(adapter.canCreateFormalTransactionAutomatically(_candidate(status: CloudInvoiceCandidateStatus.duplicate)), isFalse);
  });

  test('rejected and retryable candidates cannot become staging items', () {
    const adapter = CloudInvoiceStagingAdapter();

    expect(
      () => adapter.toStagingItem(candidate: _candidate(status: CloudInvoiceCandidateStatus.rejected), id: 'rejected'),
      throwsA(isA<CloudInvoiceStagingAdapterError>()),
    );
    expect(
      () => adapter.toStagingItem(candidate: _candidate(status: CloudInvoiceCandidateStatus.retryableError), id: 'retryable'),
      throwsA(isA<CloudInvoiceStagingAdapterError>()),
    );
  });

  test('confirmed, discarded, and blocked candidates cannot bypass staging review', () {
    const adapter = CloudInvoiceStagingAdapter();

    for (final status in <CloudInvoiceCandidateStatus>[
      CloudInvoiceCandidateStatus.confirmedDraft,
      CloudInvoiceCandidateStatus.discarded,
      CloudInvoiceCandidateStatus.blocked,
    ]) {
      expect(
        () => adapter.toStagingItem(candidate: _candidate(status: status), id: status.name),
        throwsA(isA<CloudInvoiceStagingAdapterError>()),
      );
    }
  });
}

CloudInvoiceCandidate _candidate({
  CloudInvoiceCandidateStatus status = CloudInvoiceCandidateStatus.pending,
  String sellerName = '測試便利商店',
  List<CloudInvoiceCandidateWarning> warnings = const <CloudInvoiceCandidateWarning>[],
}) {
  return CloudInvoiceCandidate(
    source: CloudInvoiceCandidateSource.mockCloudInvoice,
    status: status,
    invoiceNumber: 'AB12345678',
    invoiceDate: DateTime(2026, 6, 9),
    sellerIdentifier: '12345678',
    sellerName: sellerName,
    totalAmount: 120,
    taxAmount: 6,
    carrierType: 'mobileBarcode',
    carrierMaskedId: '/AB***12',
    fetchedAt: DateTime.utc(2026, 6, 10, 8),
    rawPayload: 'mock-cloud-invoice-payload',
    warnings: warnings,
  );
}
