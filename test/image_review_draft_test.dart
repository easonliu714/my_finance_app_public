import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/image_review_adapter.dart';
import 'package:my_finance_app/features/invoice/image_review_draft.dart';

void main() {
  test('confirmed invoice candidate creates local invoice draft', () {
    final service = ImageReviewDraftService(idFactory: () => 'draft-invoice');
    const candidate = ImageReviewCandidate(
      kind: ImageReviewCandidateKind.invoice,
      label: '發票候選',
      note: '待人工核對',
    );

    final draft = service.confirmCandidate(candidate: candidate, confirmed: true);

    expect(draft, isNotNull);
    expect(draft!.id, 'draft-invoice');
    expect(draft.kind, ImageReviewDraftKind.invoice);
    expect(draft.status, ImageReviewDraftStatus.pendingEdit);
    expect(draft.isLocalOnly, isTrue);
    expect(draft.needsEditReview, isTrue);
    expect(draft.canCreateInvoiceAutomatically, isFalse);
    expect(draft.canCreateTransactionAutomatically, isFalse);
  });

  test('confirmed product candidate creates local transaction draft', () {
    final service = ImageReviewDraftService(idFactory: () => 'draft-product');
    const candidate = ImageReviewCandidate(
      kind: ImageReviewCandidateKind.product,
      label: '商品候選',
      referenceAmount: 120,
      note: '待人工核對',
    );

    final draft = service.confirmCandidate(candidate: candidate, confirmed: true);

    expect(draft, isNotNull);
    expect(draft!.id, 'draft-product');
    expect(draft.kind, ImageReviewDraftKind.transaction);
    expect(draft.status, ImageReviewDraftStatus.pendingEdit);
    expect(draft.isLocalOnly, isTrue);
    expect(draft.needsEditReview, isTrue);
    expect(draft.canCreateInvoiceAutomatically, isFalse);
    expect(draft.canCreateTransactionAutomatically, isFalse);
  });

  test('unconfirmed candidate does not create draft', () {
    const service = ImageReviewDraftService();
    const candidate = ImageReviewCandidate(kind: ImageReviewCandidateKind.invoice, label: '發票候選');

    final draft = service.confirmCandidate(candidate: candidate, confirmed: false);

    expect(draft, isNull);
  });

  test('draft copy states confirmation and local-only boundaries', () {
    expect(ImageReviewDraftCopy.confirmationRequired, contains('使用者確認'));
    expect(ImageReviewDraftCopy.localDraftOnly, contains('不會自動寫入正式交易或發票'));
  });
}
