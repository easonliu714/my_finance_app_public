import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_multi_item_transport_evidence.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';

void main() {
  test('missing lines preserves legacy single-item transport contract', () {
    final evidence = ProductMultiItemTransportEvidence.fromCandidateJson(
      <String, Object?>{'productName': '牛奶'},
    );

    expect(evidence, isNull);
  });

  test('structured lines preserve raw evidence and remain review-only', () {
    final evidence = ProductMultiItemTransportEvidence.fromCandidateJson(
      <String, Object?>{
        'lines': <Object?>[
          <String, Object?>{
            'name': '牛奶',
            'quantity': 2,
            'unitPrice': 30,
            'subtotal': 60,
            'rawEvidence': '牛奶 2 x 30',
          },
          <String, Object?>{
            'name': '麵包',
            'quantity': 1,
            'unitPrice': 25,
            'subtotal': 25,
            'rawEvidence': '麵包 1 x 25',
          },
        ],
      },
    );

    expect(evidence, isNotNull);
    const source = ProductRecognitionCandidate(
      totalAmount: 85,
      warnings: <String>['multiple_products_visible'],
    );
    final proposal = evidence!.assembleReviewProposal(sourceCandidate: source);

    expect(proposal.reconciledTotal, 85);
    expect(proposal.lines.first.rawEvidence, '牛奶 2 x 30');
    expect(proposal.requiresUserReview, isTrue);
    expect(proposal.canCreateFormalRecord, isFalse);
  });

  test('malformed or partial rows fail closed without inference', () {
    final evidence = ProductMultiItemTransportEvidence.fromCandidateJson(
      <String, Object?>{
        'lines': <Object?>[
          'not-an-object',
          <String, Object?>{
            'name': '商品A',
            'quantity': null,
            'unitPrice': 20,
            'subtotal': null,
            'rawEvidence': '商品A 20',
          },
        ],
      },
    );

    const source = ProductRecognitionCandidate(
      totalAmount: 20,
      warnings: <String>['multiple_products_visible'],
    );
    final proposal = evidence!.assembleReviewProposal(sourceCandidate: source);

    expect(proposal.lines, hasLength(2));
    expect(proposal.hasAmbiguousLines, isTrue);
    expect(proposal.reconciledTotal, isNull);
    expect(proposal.canCreateFormalRecord, isFalse);
  });

  test('non-list lines is present but fail-closed instead of legacy fallback', () {
    final evidence = ProductMultiItemTransportEvidence.fromCandidateJson(
      <String, Object?>{'lines': 'invalid'},
    );

    expect(evidence, isNotNull);
    final proposal = evidence!.assembleReviewProposal(
      sourceCandidate: const ProductRecognitionCandidate(productName: '單品'),
    );
    expect(proposal.lines, isEmpty);
    expect(proposal.reconciledTotal, isNull);
    expect(proposal.canCreateFormalRecord, isFalse);
  });
}
