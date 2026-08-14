import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/draft_persistence_dry_run.dart';
import 'package:my_finance_app/features/invoice/draft_storage_adapter.dart';
import 'package:my_finance_app/features/invoice/image_review_adapter.dart';
import 'package:my_finance_app/features/invoice/image_review_draft.dart';

void main() {
  test('approved accepted dry-run payload is written to guarded adapter', () async {
    final adapter = InMemoryDraftStorageAdapter();
    final service = DraftStorageWriteService(adapter: adapter);
    final dryRunResult = _dryRunResult(label: '發票候選');

    final result = await service.guardedWrite(DraftStorageWriteRequest(dryRunResult: dryRunResult, approved: true));

    expect(result.accepted, isTrue);
    expect(result.payload, dryRunResult.payload);
    expect(result.isLocalOnly, isTrue);
    expect(result.requiresManualReview, isTrue);
    expect(result.canWriteFinalRecordAutomatically, isFalse);
    expect((await adapter.listDraftPayloads()).single['source_candidate_label'], '發票候選');
  });

  test('unapproved write is blocked', () async {
    final adapter = InMemoryDraftStorageAdapter();
    final service = DraftStorageWriteService(adapter: adapter);

    final result = await service.guardedWrite(DraftStorageWriteRequest(dryRunResult: _dryRunResult(label: '發票候選'), approved: false));

    expect(result.accepted, isFalse);
    expect(result.payload, isNull);
    expect(await adapter.listDraftPayloads(), isEmpty);
  });

  test('invalid dry-run payload is blocked', () async {
    final adapter = InMemoryDraftStorageAdapter();
    final service = DraftStorageWriteService(adapter: adapter);

    final result = await service.guardedWrite(DraftStorageWriteRequest(dryRunResult: _dryRunResult(label: ''), approved: true));

    expect(result.accepted, isFalse);
    expect(result.payload, isNull);
    expect(await adapter.listDraftPayloads(), isEmpty);
  });

  test('adapter copy states prototype boundary', () {
    expect(DraftStorageAdapterCopy.prototypeOnly, contains('guarded write prototype'));
    expect(DraftStorageAdapterCopy.reviewBoundary, contains('不會自動建立正式紀錄'));
  });
}

DraftPersistenceDryRunResult _dryRunResult({required String label}) {
  const service = DraftPersistenceDryRunService();
  return service.buildPayload(
    DraftPersistenceDryRunRequest(
      draft: ImageReviewDraftCandidate(
        id: 'draft-1',
        kind: ImageReviewDraftKind.invoice,
        sourceCandidate: ImageReviewCandidate(kind: ImageReviewCandidateKind.invoice, label: label),
        status: ImageReviewDraftStatus.pendingEdit,
      ),
      reviewNote: 'manual review only',
      createdAt: DateTime.utc(2026, 6, 12),
      updatedAt: DateTime.utc(2026, 6, 12),
    ),
  );
}
