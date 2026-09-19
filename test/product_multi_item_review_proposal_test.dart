import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_multi_item_review_proposal.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';

void main() {
  group('ProductMultiItemReviewProposal', () {
    test('reconciles complete multi-item rows without granting formal-write authority', () {
      const source = ProductRecognitionCandidate(
        totalAmount: 85,
        recognizedText: '咖啡 2 x 30；麵包 1 x 25；合計 85',
        warnings: <String>['multiple_products_visible'],
      );
      const proposal = ProductMultiItemReviewProposal(
        sourceCandidate: source,
        lines: <ProductReviewLineProposal>[
          ProductReviewLineProposal(
            name: '咖啡',
            quantity: 2,
            unitPrice: 30,
            subtotal: 60,
            rawEvidence: '咖啡 2 x 30',
          ),
          ProductReviewLineProposal(
            name: '麵包',
            quantity: 1,
            unitPrice: 25,
            subtotal: 25,
            rawEvidence: '麵包 1 x 25',
          ),
        ],
      );

      expect(proposal.isMultiItem, isTrue);
      expect(proposal.hasAmbiguousLines, isFalse);
      expect(proposal.reconciledTotal, 85);
      expect(proposal.reconcilesObservedTotal(), isTrue);
      expect(proposal.requiresUserReview, isTrue);
      expect(proposal.canCreateFormalRecord, isFalse);
    });

    test('missing or inconsistent values remain review-required and unreconciled', () {
      const proposal = ProductMultiItemReviewProposal(
        sourceCandidate: ProductRecognitionCandidate(totalAmount: 100),
        lines: <ProductReviewLineProposal>[
          ProductReviewLineProposal(
            name: '商品 A',
            quantity: 2,
            unitPrice: 20,
            subtotal: 50,
            rawEvidence: '商品 A 2 x 20 ? 50',
          ),
          ProductReviewLineProposal(name: '商品 B', rawEvidence: '商品 B'),
        ],
      );

      expect(proposal.hasAmbiguousLines, isTrue);
      expect(proposal.reconciledTotal, isNull);
      expect(proposal.reconcilesObservedTotal(), isFalse);
      expect(proposal.canCreateFormalRecord, isFalse);
    });

    test('single-item proposal keeps the same review-only boundary', () {
      const proposal = ProductMultiItemReviewProposal(
        sourceCandidate: ProductRecognitionCandidate(totalAmount: 40),
        lines: <ProductReviewLineProposal>[
          ProductReviewLineProposal(
            name: '商品',
            quantity: 2,
            unitPrice: 20,
            subtotal: 40,
            rawEvidence: '商品 2 x 20',
          ),
        ],
      );

      expect(proposal.isMultiItem, isFalse);
      expect(proposal.reconciledTotal, 40);
      expect(proposal.reconcilesObservedTotal(), isTrue);
      expect(proposal.requiresUserReview, isTrue);
      expect(proposal.canCreateFormalRecord, isFalse);
    });
  });
}
