import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_import_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_qr_import_staging_service.dart';

void main() {
  const service = InvoiceQrImportStagingService();
  const validPayload = 'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

  test('createBatchFromPayloads converts valid QR payloads into pending staging items', () {
    final result = service.createBatchFromPayloads(
      batchId: 'batch-1',
      rawPayloads: const [validPayload],
      sellerNameResolver: (_) => '測試便利商店',
      now: DateTime.utc(2026, 6, 10),
    );

    expect(result.rejectedPayloads, isEmpty);
    expect(result.batch.items, hasLength(1));
    final item = result.batch.items.single;
    expect(item.id, 'batch-1-qr-1');
    expect(item.source, InvoiceImportStagingSource.qrParser);
    expect(item.status, InvoiceImportStagingStatus.pending);
    expect(item.invoiceNumber, 'AB12345678');
    expect(item.sellerName, '測試便利商店');
    expect(item.totalAmount, 120);
    expect(item.rawPayload, validPayload);
  });

  test('createBatchFromPayloads collects invalid and unsupported payloads without throwing', () {
    final result = service.createBatchFromPayloads(
      batchId: 'batch-2',
      rawPayloads: const [validPayload, 'AB123', '**商品明細'],
      now: DateTime.utc(2026, 6, 10),
    );

    expect(result.batch.items, hasLength(1));
    expect(result.rejectedPayloads, hasLength(2));
    expect(result.rejectedPayloads[0].index, 1);
    expect(result.rejectedPayloads[0].errors, contains('QR payload 長度不足，無法解析電子發票左方 QR 基本資料'));
    expect(result.rejectedPayloads[1].index, 2);
    expect(result.rejectedPayloads[1].errors, contains('目前 POC 僅支援電子發票左方 QR 基本資料，不支援右方明細 QR'));
  });

  test('createBatchFromPayloads reuses staging duplicate detection', () {
    final result = service.createBatchFromPayloads(
      batchId: 'batch-3',
      rawPayloads: const [validPayload, validPayload],
      now: DateTime.utc(2026, 6, 10),
    );

    expect(result.batch.items, hasLength(2));
    expect(result.batch.pendingCount, 1);
    expect(result.batch.duplicateCount, 1);
    expect(result.batch.items.first.status, InvoiceImportStagingStatus.pending);
    expect(result.batch.items.last.status, InvoiceImportStagingStatus.duplicate);
  });
}
