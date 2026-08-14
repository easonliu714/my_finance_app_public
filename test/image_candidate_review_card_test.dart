import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/image_candidate_review_card.dart';
import 'package:my_finance_app/features/invoice/image_review_adapter.dart';

void main() {
  testWidgets('ImageCandidateReviewCard renders blocked state', (tester) async {
    const result = ImageReviewAdapterResult(
      status: ImageReviewAdapterStatus.blockedByConsent,
      candidates: <ImageReviewCandidate>[],
      message: '需先取得同意，才可建立辨識候選。',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImageCandidateReviewCard(result: result))),
    );

    expect(find.byKey(ImageCandidateReviewCard.cardKey), findsOneWidget);
    expect(find.byKey(ImageCandidateReviewCard.blockedStateKey), findsOneWidget);
    expect(find.text('辨識候選審核'), findsOneWidget);
    expect(find.text('等待同意'), findsOneWidget);
    expect(find.text('需同意'), findsOneWidget);
    expect(find.textContaining('不會自動建立交易'), findsOneWidget);
  });

  testWidgets('ImageCandidateReviewCard renders invoice candidate distinctly', (tester) async {
    const result = ImageReviewAdapterResult(
      status: ImageReviewAdapterStatus.readyForReview,
      candidates: <ImageReviewCandidate>[
        ImageReviewCandidate(kind: ImageReviewCandidateKind.invoice, label: '發票候選', note: '待人工核對號碼'),
      ],
      message: '已建立發票辨識候選，需人工確認。',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImageCandidateReviewCard(result: result))),
    );

    expect(find.byKey(ImageCandidateReviewCard.readyStateKey), findsOneWidget);
    expect(find.text('發票候選'), findsOneWidget);
    expect(find.textContaining('發票'), findsAtLeastNWidgets(1));
    expect(find.text('待審核'), findsOneWidget);
    expect(find.byKey(ImageCandidateReviewCard.acceptActionKey), findsOneWidget);
    expect(find.byKey(ImageCandidateReviewCard.editActionKey), findsOneWidget);
    expect(find.byKey(ImageCandidateReviewCard.discardActionKey), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(ImageCandidateReviewCard.acceptActionKey)).onPressed, isNull);
  });

  testWidgets('ImageCandidateReviewCard renders product candidate distinctly', (tester) async {
    const result = ImageReviewAdapterResult(
      status: ImageReviewAdapterStatus.readyForReview,
      candidates: <ImageReviewCandidate>[
        ImageReviewCandidate(kind: ImageReviewCandidateKind.product, label: '商品候選', referenceAmount: 120, note: '待人工核對價格'),
      ],
      message: '已建立商品辨識候選，需人工確認。',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImageCandidateReviewCard(result: result))),
    );

    expect(find.byKey(ImageCandidateReviewCard.readyStateKey), findsOneWidget);
    expect(find.text('商品候選'), findsOneWidget);
    expect(find.textContaining('商品'), findsAtLeastNWidgets(1));
    expect(find.textContaining('參考金額 120'), findsOneWidget);
  });

  testWidgets('ImageCandidateReviewCard renders failed state', (tester) async {
    const result = ImageReviewAdapterResult(
      status: ImageReviewAdapterStatus.failed,
      candidates: <ImageReviewCandidate>[],
      message: '辨識失敗。',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImageCandidateReviewCard(result: result))),
    );

    expect(find.byKey(ImageCandidateReviewCard.failedStateKey), findsOneWidget);
    expect(find.text('辨識失敗'), findsOneWidget);
    expect(find.text('失敗'), findsOneWidget);
  });
}
