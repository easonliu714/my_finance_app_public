import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_recognition_execution_review_evidence.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

void main() {
  test('execution review evidence stays proposal-only and user-reviewed', () {
    final reviewResult = ProductRecognitionReviewResult(
      candidate: ProductRecognitionCandidate.fromJson(<String, dynamic>{
        'productName': '測試商品',
        'unitPrice': 10,
        'quantity': 2,
        'totalAmount': 20,
      }),
    );

    final evidence =
        ProductRecognitionExecutionReviewEvidence.fromReviewResult(reviewResult);

    expect(evidence.reviewResult, same(reviewResult));
    expect(evidence.requiresUserReview, isTrue);
    expect(evidence.canCreateFormalRecord, isFalse);
    expect(evidence.multiItemProposal, reviewResult.multiItemProposal);
    expect(evidence.toSafeSummary(), <String, Object?>{
      'requiresUserReview': true,
      'canCreateFormalRecord': false,
      'hasMultiItemProposal': false,
    });
  });
}
