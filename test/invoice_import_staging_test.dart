import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_import_staging.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft.dart';

void main() {
  test('createBatch marks repeated duplicate keys as duplicate', () {
    final service = InvoiceImportStagingService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final first = _stagingItem(id: 'item-1');
    final second = _stagingItem(id: 'item-2');

    final batch = service.createBatch(id: 'batch-1', items: <InvoiceImportStagingItem>[first, second]);

    expect(batch.items, hasLength(2));
    expect(batch.items.first.status, InvoiceImportStagingStatus.pending);
    expect(batch.items.last.status, InvoiceImportStagingStatus.duplicate);
    expect(batch.pendingCount, 1);
    expect(batch.duplicateCount, 1);
  });

  test('createBatch does not override an explicit non-pending status when duplicate key repeats', () {
    final service = InvoiceImportStagingService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final first = _stagingItem(id: 'item-1');
    final rejectedSecond = _stagingItem(id: 'item-2', status: InvoiceImportStagingStatus.rejected);

    final batch = service.createBatch(id: 'batch-1', items: <InvoiceImportStagingItem>[first, rejectedSecond]);

    expect(batch.items.last.status, InvoiceImportStagingStatus.rejected);
    expect(batch.rejectedCount, 1);
    expect(batch.duplicateCount, 0);
  });

  test('staging status metadata exposes labels, review flags, and terminal state', () {
    expect(InvoiceImportStagingStatus.pending.metadata.label, '待確認');
    expect(InvoiceImportStagingStatus.pending.metadata.requiresUserReview, isTrue);
    expect(InvoiceImportStagingStatus.duplicate.metadata.label, '疑似重複');
    expect(InvoiceImportStagingStatus.duplicate.metadata.requiresUserReview, isTrue);
    expect(InvoiceImportStagingStatus.accepted.metadata.canConvertToDraft, isTrue);
    expect(InvoiceImportStagingStatus.converted.metadata.isTerminal, isTrue);
  });

  test('staging item exposes status helper values', () {
    final pending = _stagingItem(id: 'item-1');
    final accepted = pending.copyWith(status: InvoiceImportStagingStatus.accepted);
    final converted = pending.copyWith(status: InvoiceImportStagingStatus.converted);

    expect(pending.statusLabel, '待確認');
    expect(pending.requiresUserReview, isTrue);
    expect(pending.isConvertible, isFalse);
    expect(accepted.statusLabel, '已接受');
    expect(accepted.isConvertible, isTrue);
    expect(converted.isTerminal, isTrue);
  });

  test('status transition matrix allows only explicit review lifecycle paths', () {
    expect(InvoiceImportStagingStatus.pending.canTransitionTo(InvoiceImportStagingStatus.accepted), isTrue);
    expect(InvoiceImportStagingStatus.pending.canTransitionTo(InvoiceImportStagingStatus.rejected), isTrue);
    expect(InvoiceImportStagingStatus.pending.canTransitionTo(InvoiceImportStagingStatus.duplicate), isTrue);
    expect(InvoiceImportStagingStatus.pending.canTransitionTo(InvoiceImportStagingStatus.converted), isFalse);

    expect(InvoiceImportStagingStatus.duplicate.canTransitionTo(InvoiceImportStagingStatus.accepted), isTrue);
    expect(InvoiceImportStagingStatus.accepted.canTransitionTo(InvoiceImportStagingStatus.converted), isTrue);
    expect(InvoiceImportStagingStatus.rejected.canTransitionTo(InvoiceImportStagingStatus.converted), isFalse);
    expect(InvoiceImportStagingStatus.converted.canTransitionTo(InvoiceImportStagingStatus.pending), isFalse);
  });

  test('statusCounts summarizes staging lifecycle states', () {
    final batch = InvoiceImportStagingBatch(
      id: 'batch-1',
      items: <InvoiceImportStagingItem>[
        _stagingItem(id: 'item-1'),
        _stagingItem(id: 'item-2', status: InvoiceImportStagingStatus.accepted),
        _stagingItem(id: 'item-3', status: InvoiceImportStagingStatus.rejected),
        _stagingItem(id: 'item-4', status: InvoiceImportStagingStatus.duplicate),
        _stagingItem(id: 'item-5', status: InvoiceImportStagingStatus.converted),
      ],
    );

    expect(batch.statusCounts[InvoiceImportStagingStatus.pending], 1);
    expect(batch.statusCounts[InvoiceImportStagingStatus.accepted], 1);
    expect(batch.statusCounts[InvoiceImportStagingStatus.rejected], 1);
    expect(batch.statusCounts[InvoiceImportStagingStatus.duplicate], 1);
    expect(batch.statusCounts[InvoiceImportStagingStatus.converted], 1);
  });

  test('accepted staging item converts to manual invoice draft candidate explicitly', () {
    final service = InvoiceImportStagingService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final accepted = service.updateStatus(
      item: _stagingItem(id: 'item-1'),
      status: InvoiceImportStagingStatus.accepted,
    );

    final draft = service.convertAcceptedItem(item: accepted, draftId: 'draft-1');

    expect(draft.id, 'draft-1');
    expect(draft.invoiceNumber, 'AB12345678');
    expect(draft.invoiceDate, DateTime(2026, 6, 9));
    expect(draft.sellerName, '測試便利商店');
    expect(draft.totalAmount, 120);
    expect(draft.status, ManualInvoiceDraftStatus.readyToReview);
    expect(draft.createdAt, DateTime.utc(2026, 6, 10, 8, 0));
  });

  test('pending staging item cannot be converted silently', () {
    final service = InvoiceImportStagingService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));

    expect(
      () => service.convertAcceptedItem(item: _stagingItem(id: 'item-1'), draftId: 'draft-1'),
      throwsA(isA<InvoiceImportStagingTransitionError>()),
    );
  });

  test('rejected and duplicate staging items cannot be converted', () {
    final service = InvoiceImportStagingService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final rejected = service.updateStatus(
      item: _stagingItem(id: 'item-1'),
      status: InvoiceImportStagingStatus.rejected,
    );
    final duplicate = service.updateStatus(
      item: _stagingItem(id: 'item-2'),
      status: InvoiceImportStagingStatus.duplicate,
    );

    expect(
      () => service.convertAcceptedItem(item: rejected, draftId: 'draft-1'),
      throwsA(isA<InvoiceImportStagingTransitionError>()),
    );
    expect(
      () => service.convertAcceptedItem(item: duplicate, draftId: 'draft-2'),
      throwsA(isA<InvoiceImportStagingTransitionError>()),
    );
  });

  test('converted staging item cannot be changed again', () {
    final service = InvoiceImportStagingService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final accepted = service.updateStatus(
      item: _stagingItem(id: 'item-1'),
      status: InvoiceImportStagingStatus.accepted,
    );
    final converted = service.updateStatus(
      item: accepted,
      status: InvoiceImportStagingStatus.converted,
    );

    expect(
      () => service.updateStatus(item: converted, status: InvoiceImportStagingStatus.rejected),
      throwsA(isA<InvoiceImportStagingTransitionError>()),
    );
  });

  test('service helpers follow the same transition rules', () {
    final service = InvoiceImportStagingService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final pending = _stagingItem(id: 'item-1');
    final duplicate = service.markDuplicate(pending);
    final accepted = service.acceptItem(duplicate);
    final converted = service.markConverted(accepted);

    expect(duplicate.status, InvoiceImportStagingStatus.duplicate);
    expect(accepted.status, InvoiceImportStagingStatus.accepted);
    expect(converted.status, InvoiceImportStagingStatus.converted);
  });
}

InvoiceImportStagingItem _stagingItem({required String id, InvoiceImportStagingStatus status = InvoiceImportStagingStatus.pending}) {
  return InvoiceImportStagingItem(
    id: id,
    source: InvoiceImportStagingSource.qrParser,
    invoiceNumber: 'AB12345678',
    invoiceDate: DateTime(2026, 6, 9),
    sellerName: '測試便利商店',
    totalAmount: 120,
    taxAmount: 6,
    note: 'QR 匯入候選',
    rawPayload: 'raw-qr-payload',
    status: status,
  );
}
