import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft_repository.dart';

void main() {
  test('saveDraft persists and reloads a manual invoice draft locally', () async {
    final repository = InMemoryManualInvoiceDraftRepository(clock: () => DateTime.utc(2026, 6, 9, 2, 0));
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'ab12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
      taxAmount: 6,
      note: '早餐',
      status: ManualInvoiceDraftStatus.readyToReview,
      createdAt: DateTime.utc(2026, 6, 9, 1, 0),
    );

    final saved = await repository.saveDraft(draft);
    final loaded = await repository.loadDraftById('draft-1');

    expect(saved.id, 'draft-1');
    expect(saved.updatedAt, DateTime.utc(2026, 6, 9, 2, 0));
    expect(loaded?.invoiceNumber, 'ab12345678');
    expect(loaded?.status, ManualInvoiceDraftStatus.readyToReview);
  });

  test('saveDraft prevents duplicate active invoice drafts', () async {
    final repository = InMemoryManualInvoiceDraftRepository(clock: () => DateTime.utc(2026, 6, 9, 2, 0));
    final first = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
      status: ManualInvoiceDraftStatus.readyToReview,
    );
    final duplicate = ManualInvoiceDraft(
      id: 'draft-2',
      invoiceNumber: 'ab12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
      status: ManualInvoiceDraftStatus.readyToReview,
    );

    await repository.saveDraft(first);

    expect(
      () => repository.saveDraft(duplicate),
      throwsA(isA<ManualInvoiceDraftDuplicateError>()),
    );
  });

  test('updateStatus changes draft lifecycle without creating transaction', () async {
    final repository = InMemoryManualInvoiceDraftRepository(clock: () => DateTime.utc(2026, 6, 9, 3, 0));
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
      status: ManualInvoiceDraftStatus.readyToReview,
    );

    await repository.saveDraft(draft);
    final updated = await repository.updateStatus(id: 'draft-1', status: ManualInvoiceDraftStatus.readyToConfirm);

    expect(updated.status, ManualInvoiceDraftStatus.readyToConfirm);
    expect(updated.updatedAt, DateTime.utc(2026, 6, 9, 3, 0));
  });

  test('loadDrafts filters by status and returns latest first', () async {
    final repository = InMemoryManualInvoiceDraftRepository();
    await repository.saveDraft(
      ManualInvoiceDraft(
        id: 'draft-old',
        invoiceNumber: 'AA12345678',
        invoiceDate: DateTime(2026, 6, 1),
        sellerName: 'A 店',
        totalAmount: 10,
        status: ManualInvoiceDraftStatus.draft,
        updatedAt: DateTime.utc(2026, 6, 1),
      ),
    );
    await repository.saveDraft(
      ManualInvoiceDraft(
        id: 'draft-new',
        invoiceNumber: 'BB12345678',
        invoiceDate: DateTime(2026, 6, 2),
        sellerName: 'B 店',
        totalAmount: 20,
        status: ManualInvoiceDraftStatus.readyToReview,
        updatedAt: DateTime.utc(2026, 6, 2),
      ),
    );

    final readyDrafts = await repository.loadDrafts(status: ManualInvoiceDraftStatus.readyToReview);

    expect(readyDrafts, hasLength(1));
    expect(readyDrafts.single.id, 'draft-new');
  });

  test('deleteDraft removes local draft', () async {
    final repository = InMemoryManualInvoiceDraftRepository();
    await repository.saveDraft(
      ManualInvoiceDraft(
        id: 'draft-1',
        invoiceNumber: 'AB12345678',
        invoiceDate: DateTime(2026, 6, 9),
        sellerName: '測試便利商店',
        totalAmount: 120,
      ),
    );

    await repository.deleteDraft('draft-1');

    expect(await repository.loadDraftById('draft-1'), isNull);
  });
}
