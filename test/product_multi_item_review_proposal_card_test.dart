import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_multi_item_review_proposal.dart';
import 'package:my_finance_app/features/product/product_multi_item_review_proposal_card.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';

void main() {
  const sourceCandidate = ProductRecognitionCandidate(
    name: '購物明細',
    totalAmount: 75,
  );

  testWidgets('renders same-request multi-item proposal as review-only UI',
      (tester) async {
    const proposal = ProductMultiItemReviewProposal(
      sourceCandidate: sourceCandidate,
      lines: <ProductReviewLineProposal>[
        ProductReviewLineProposal(
          name: '咖啡',
          quantity: 2,
          unitPrice: 30,
          subtotal: 60,
        ),
        ProductReviewLineProposal(
          name: '袋子',
          quantity: 1,
          unitPrice: 15,
          subtotal: 15,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProductMultiItemReviewProposalCard(proposal: proposal),
        ),
      ),
    );

    expect(find.byKey(ProductMultiItemReviewProposalCard.titleKey), findsOneWidget);
    expect(find.textContaining('咖啡'), findsOneWidget);
    expect(find.textContaining('袋子'), findsOneWidget);
    expect(find.byKey(ProductMultiItemReviewProposalCard.totalKey), findsOneWidget);
    expect(find.textContaining('不會自動建立正式記帳'), findsOneWidget);
    expect(proposal.requiresUserReview, isTrue);
    expect(proposal.canCreateFormalRecord, isFalse);
  });

  testWidgets('surfaces incomplete calculation as explicit review warning',
      (tester) async {
    const proposal = ProductMultiItemReviewProposal(
      sourceCandidate: sourceCandidate,
      lines: <ProductReviewLineProposal>[
        ProductReviewLineProposal(name: '待確認商品', quantity: 1),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProductMultiItemReviewProposalCard(proposal: proposal),
        ),
      ),
    );

    expect(find.byKey(ProductMultiItemReviewProposalCard.warningKey), findsOneWidget);
    expect(find.textContaining('需要人工確認'), findsWidgets);
    expect(find.byKey(ProductMultiItemReviewProposalCard.totalKey), findsNothing);
  });
}
