import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/draft_persistence_dry_run.dart';
import 'package:my_finance_app/features/invoice/image_review_adapter.dart';
import 'package:my_finance_app/features/invoice/image_review_draft.dart';

void main() {
  test('invoice draft builds accepted dry-run payload', () {
    const service = DraftPersistenceDryRunService();
    final result = service.buildPayload(_request(_draft(ImageReviewDraftKind.invoice, ImageReviewCandidateKind.invoice, '發票候選')));

    expect(result.accepted, isTrue);
    expect(result.missingFields, isEmpty);
    expect(result.payload['draft_kind'], 'invoice');
    expect(result.payload['source_candidate_kind'], 'invoice');
    expect(result.isLocalOnly, isTrue);
    expect(result.requiresManualReview, isTrue);
    expect(result.canWriteRuntimeStorage, isFalse);
    expect(result.canCreateFinalRecordAutomatically, isFalse);
  });

  test('transaction draft builds accepted dry-run payload', () {
    const service = DraftPersistenceDryRunService();
    final result = service.buildPayload(_request(_draft(ImageReviewDraftKind.transaction, ImageReviewCandidateKind.product, '商品候選')));

    expect(result.accepted, isTrue);
    expect(result.payload['draft_kind'], 'transaction');
    expect(result.payload['source_candidate_kind'], 'product');
    expect(result.canWriteRuntimeStorage, isFalse);
    expect(result.canCreateFinalRecordAutomatically, isFalse);
  });

  test('missing required field is detected', () {
    const service = DraftPersistenceDryRunService();
    final result = service.buildPayload(_request(_draft(ImageReviewDraftKind.invoice, ImageReviewCandidateKind.invoice, '')));

    expect(result.accepted, isFalse);
    expect(result.missingFields, contains('source_candidate_label'));
  });

  test('dry-run copy states runtime write boundary', () {
    expect(DraftPersistenceDryRunCopy.dryRunOnly, contains('dry-run payload'));
    expect(DraftPersistenceDryRunCopy.reviewOnly, contains('不會自動建立正式紀錄'));
  });
}

DraftPersistenceDryRunRequest _request(ImageReviewDraftCandidate draft) {
  return DraftPersistenceDryRunRequest(
    draft: draft,
    reviewNote: 'manual review only',
    createdAt: DateTime.utc(2026, 6, 12),
    updatedAt: DateTime.utc(2026, 6, 12),
  );
}

ImageReviewDraftCandidate _draft(ImageReviewDraftKind kind, ImageReviewCandidateKind candidateKind, String label) {
  return ImageReviewDraftCandidate(
    id: 'draft-${kind.name}',
    kind: kind,
    sourceCandidate: ImageReviewCandidate(kind: candidateKind, label: label),
    status: ImageReviewDraftStatus.pendingEdit,
  );
}
