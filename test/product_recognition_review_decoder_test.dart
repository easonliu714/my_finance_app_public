import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_recognition_review_decoder.dart';

void main() {
  Map<String, Object?> legacyCandidate({Object? lines}) => <String, Object?>{
        'productName': '牛奶',
        'quantity': 1,
        'unitPrice': 60,
        'totalAmount': 60,
        'categorySuggestion': '食品',
        'merchantName': null,
        'recognizedText': '牛奶 60',
        'confidence': <String, Object?>{},
        'warnings': <String>[],
        if (lines != null) 'lines': lines,
      };

  test('missing lines preserves legacy candidate and no multi-item proposal', () {
    final result = ProductRecognitionReviewDecoder.decode(legacyCandidate());

    expect(result.candidate.productName, '牛奶');
    expect(result.multiItemProposal, isNull);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('explicit lines become a separate review-only proposal', () {
    final result = ProductRecognitionReviewDecoder.decode(
      legacyCandidate(
        lines: <Object?>[
          <String, Object?>{
            'name': '牛奶',
            'quantity': 1,
            'unitPrice': 30,
            'subtotal': 30,
            'rawEvidence': '牛奶 30',
          },
          <String, Object?>{
            'name': '麵包',
            'quantity': 1,
            'unitPrice': 30,
            'subtotal': 30,
            'rawEvidence': '麵包 30',
          },
        ],
      ),
    );

    final proposal = result.multiItemProposal;
    expect(proposal, isNotNull);
    expect(proposal!.lines, hasLength(2));
    expect(proposal.reconciledTotal, 60);
    expect(proposal.reconcilesObservedTotal(), isTrue);
    expect(proposal.requiresUserReview, isTrue);
    expect(proposal.canCreateFormalRecord, isFalse);
  });

  test('malformed lines fail closed as ambiguous review evidence', () {
    final result = ProductRecognitionReviewDecoder.decode(
      legacyCandidate(lines: <Object?>['not-a-row']),
    );

    final proposal = result.multiItemProposal;
    expect(proposal, isNotNull);
    expect(proposal!.hasAmbiguousLines, isTrue);
    expect(proposal.reconciledTotal, isNull);
    expect(proposal.canCreateFormalRecord, isFalse);
  });
}
