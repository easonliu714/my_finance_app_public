import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/image_review_adapter.dart';
import 'package:my_finance_app/features/invoice/image_review_draft.dart';
import 'package:my_finance_app/features/invoice/image_review_draft_persistence.dart';

void main() {
  test('confirmed invoice draft is accepted into local review store', () async {
    final store = InMemoryImageReviewDraftStore();
    final service = ImageReviewDraftPersistenceService(store: store);
    final draft = _draft(kind: ImageReviewDraftKind.invoice, candidateKind: ImageReviewCandidateKind.invoice);

    final result = await service.persistForReview(ImageReviewDraftPersistenceRequest(draft: draft, confirmed: true));

    expect(result.status, ImageReviewDraftPersistenceStatus.acceptedForLocalReview);
    expect(result.draft, draft);
    expect(result.isLocalOnly, isTrue);
    expect(result.needsFinalReview, isTrue);
    expect(result.canWriteFinalInvoiceAutomatically, isFalse);
    expect(result.canWriteFinalTransactionAutomatically, isFalse);
    expect(await store.listPendingReviewDrafts(), <ImageReviewDraftCandidate>[draft]);
  });

  test('confirmed transaction draft is accepted into local review store', () async {
    final store = InMemoryImageReviewDraftStore();
    final service = ImageReviewDraftPersistenceService(store: store);
    final draft = _draft(kind: ImageReviewDraftKind.transaction, candidateKind: ImageReviewCandidateKind.product);

    final result = await service.persistForReview(ImageReviewDraftPersistenceRequest(draft: draft, confirmed: true));

    expect(result.status, ImageReviewDraftPersistenceStatus.acceptedForLocalReview);
    expect(result.draft!.kind, ImageReviewDraftKind.transaction);
    expect(result.canWriteFinalInvoiceAutomatically, isFalse);
    expect(result.canWriteFinalTransactionAutomatically, isFalse);
    expect((await store.listPendingReviewDrafts()).single.kind, ImageReviewDraftKind.transaction);
  });

  test('unconfirmed draft persistence is blocked', () async {
    final store = InMemoryImageReviewDraftStore();
    final service = ImageReviewDraftPersistenceService(store: store);
    final draft = _draft(kind: ImageReviewDraftKind.invoice, candidateKind: ImageReviewCandidateKind.invoice);

    final result = await service.persistForReview(ImageReviewDraftPersistenceRequest(draft: draft, confirmed: false));

    expect(result.status, ImageReviewDraftPersistenceStatus.blockedByConfirmation);
    expect(result.draft, isNull);
    expect(result.isLocalOnly, isTrue);
    expect(result.needsFinalReview, isFalse);
    expect(await store.listPendingReviewDrafts(), isEmpty);
  });

  test('persistence copy states review boundary', () {
    expect(ImageReviewDraftPersistenceCopy.confirmationRequired, contains('確認本機草稿'));
    expect(ImageReviewDraftPersistenceCopy.reviewBoundary, contains('不會自動寫入正式交易或發票'));
  });
}

ImageReviewDraftCandidate _draft({required ImageReviewDraftKind kind, required ImageReviewCandidateKind candidateKind}) {
  return ImageReviewDraftCandidate(
    id: 'draft-${kind.name}',
    kind: kind,
    sourceCandidate: ImageReviewCandidate(kind: candidateKind, label: '${kind.name} candidate'),
    status: ImageReviewDraftStatus.pendingEdit,
  );
}
