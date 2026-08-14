import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/image_review_adapter.dart';
import 'package:my_finance_app/features/invoice/image_review_draft.dart';
import 'package:my_finance_app/features/invoice/image_review_draft_card.dart';

void main() {
  testWidgets('ImageReviewDraftCard renders invoice draft distinctly', (tester) async {
    const draft = ImageReviewDraftCandidate(
      id: 'draft-invoice',
      kind: ImageReviewDraftKind.invoice,
      sourceCandidate: ImageReviewCandidate(kind: ImageReviewCandidateKind.invoice, label: '發票候選'),
      status: ImageReviewDraftStatus.pendingEdit,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImageReviewDraftCard(draft: draft))),
    );

    expect(find.byKey(ImageReviewDraftCard.cardKey), findsOneWidget);
    expect(find.byKey(ImageReviewDraftCard.invoiceDraftKey), findsOneWidget);
    expect(find.text('本機草稿審核'), findsOneWidget);
    expect(find.text('發票草稿'), findsOneWidget);
    expect(find.textContaining('發票候選'), findsOneWidget);
    expect(find.text('待編輯確認'), findsOneWidget);
    expect(find.textContaining('不會自動寫入正式交易或發票'), findsOneWidget);
    expect(tester.widget<ImageReviewDraftCard>(find.byType(ImageReviewDraftCard)).canWriteFinalRecordAutomatically, isFalse);
  });

  testWidgets('ImageReviewDraftCard renders transaction draft distinctly', (tester) async {
    const draft = ImageReviewDraftCandidate(
      id: 'draft-product',
      kind: ImageReviewDraftKind.transaction,
      sourceCandidate: ImageReviewCandidate(kind: ImageReviewCandidateKind.product, label: '商品候選'),
      status: ImageReviewDraftStatus.pendingEdit,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImageReviewDraftCard(draft: draft))),
    );

    expect(find.byKey(ImageReviewDraftCard.transactionDraftKey), findsOneWidget);
    expect(find.text('交易草稿'), findsOneWidget);
    expect(find.textContaining('商品候選'), findsOneWidget);
    expect(find.text('待編輯確認'), findsOneWidget);
  });

  testWidgets('ImageReviewDraftCard keeps review actions disabled', (tester) async {
    const draft = ImageReviewDraftCandidate(
      id: 'draft-invoice',
      kind: ImageReviewDraftKind.invoice,
      sourceCandidate: ImageReviewCandidate(kind: ImageReviewCandidateKind.invoice, label: '發票候選'),
      status: ImageReviewDraftStatus.pendingEdit,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImageReviewDraftCard(draft: draft))),
    );

    expect(find.byKey(ImageReviewDraftCard.editActionKey), findsOneWidget);
    expect(find.byKey(ImageReviewDraftCard.confirmActionKey), findsOneWidget);
    expect(find.byKey(ImageReviewDraftCard.discardActionKey), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(ImageReviewDraftCard.editActionKey)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(ImageReviewDraftCard.confirmActionKey)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(ImageReviewDraftCard.discardActionKey)).onPressed, isNull);
  });
}
