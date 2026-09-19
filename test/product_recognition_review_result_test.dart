import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

void main() {
  test('missing lines preserves legacy candidate without multi-item proposal', () {
    final result = ProductRecognitionReviewResult.fromCandidateJson(
      <String, Object?>{
        'productName': '咖啡',
        'quantity': 1,
        'unitPrice': 60,
        'totalAmount': 60,
      },
    );

    expect(result.candidate.productName, '咖啡');
    expect(result.multiItemProposal, isNull);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('valid optional lines become a separate review-only proposal', () {
    final result = ProductRecognitionReviewResult.fromCandidateJson(
      <String, Object?>{
        'productName': '多項商品',
        'totalAmount': 100,
        'warnings': <String>['multiple_products_visible'],
        'lines': <Object?>[
          <String, Object?>{
            'name': '咖啡',
            'quantity': 1,
            'unitPrice': 60,
            'subtotal': 60,
            'rawEvidence': '咖啡 1 60 60',
          },
          <String, Object?>{
            'name': '麵包',
            'quantity': 2,
            'unitPrice': 20,
            'subtotal': 40,
            'rawEvidence': '麵包 2 20 40',
          },
        ],
      },
    );

    expect(result.candidate.hasMultipleProducts, isTrue);
    expect(result.multiItemProposal, isNotNull);
    expect(result.multiItemProposal!.lines, hasLength(2));
    expect(result.multiItemProposal!.reconciledTotal, 100);
    expect(result.multiItemProposal!.reconcilesObservedTotal(), isTrue);
    expect(result.multiItemProposal!.requiresUserReview, isTrue);
    expect(result.multiItemProposal!.canCreateFormalRecord, isFalse);
  });

  test('malformed lines fail closed as ambiguous review evidence', () {
    final result = ProductRecognitionReviewResult.fromCandidateJson(
      <String, Object?>{
        'productName': '多項商品',
        'totalAmount': 100,
        'lines': <Object?>[
          'not-a-row',
          <String, Object?>{
            'name': '咖啡',
            'quantity': 1,
            'unitPrice': 60,
            'subtotal': 50,
            'rawEvidence': 'conflicting subtotal',
          },
        ],
      },
    );

    expect(result.multiItemProposal, isNotNull);
    expect(result.multiItemProposal!.hasAmbiguousLines, isTrue);
    expect(result.multiItemProposal!.reconciledTotal, isNull);
    expect(result.multiItemProposal!.reconcilesObservedTotal(), isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });
}
