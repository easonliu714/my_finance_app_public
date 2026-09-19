import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_multi_item_review_proposal.dart';
import 'package:my_finance_app/features/product/product_multi_item_review_proposal_card.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_recognition_execution_review_evidence.dart';
import 'package:my_finance_app/features/product/product_recognition_execution_review_proposal_card.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

void main() {
  const candidate = ProductRecognitionCandidate(
    productName: '購物明細',
    totalAmount: 75,
  );

  testWidgets('null legacy evidence renders no compact review proposal',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProductRecognitionExecutionReviewProposalCard(evidence: null),
        ),
      ),
    );

    expect(find.byType(ProductMultiItemReviewProposalCard), findsNothing);
  });

  testWidgets('same-request execution evidence renders compact proposal once',
      (tester) async {
    const proposal = ProductMultiItemReviewProposal(
      sourceCandidate: candidate,
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
    final evidence = ProductRecognitionExecutionReviewEvidence.fromReviewResult(
      const ProductRecognitionReviewResult(
        candidate: candidate,
        multiItemProposal: proposal,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductRecognitionExecutionReviewProposalCard(
            evidence: evidence,
          ),
        ),
      ),
    );

    expect(find.byType(ProductMultiItemReviewProposalCard), findsOneWidget);
    expect(find.textContaining('咖啡'), findsOneWidget);
    expect(find.textContaining('不會自動建立正式記帳'), findsOneWidget);
    expect(evidence.requiresUserReview, isTrue);
    expect(evidence.canCreateFormalRecord, isFalse);
  });
}
