import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_multi_item_proposal_assembler.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';

void main() {
  const assembler = ProductMultiItemProposalAssembler();

  test('assembles explicit line evidence without formal-write authority', () {
    const source = ProductRecognitionCandidate(
      totalAmount: 85,
      recognizedText: '牛奶 2 x 30; 麵包 1 x 25; 合計 85',
      warnings: <String>['multiple_products_visible'],
    );

    final proposal = assembler.assemble(
      sourceCandidate: source,
      rawLines: <Map<String, Object?>>[
        <String, Object?>{
          'name': '牛奶',
          'quantity': 2,
          'unitPrice': 30,
          'subtotal': 60,
          'rawEvidence': '牛奶 2 x 30',
        },
        <String, Object?>{
          'name': '麵包',
          'quantity': '1',
          'unitPrice': '25',
          'subtotal': '25',
          'rawEvidence': '麵包 1 x 25',
        },
      ],
    );

    expect(proposal.isMultiItem, isTrue);
    expect(proposal.hasAmbiguousLines, isFalse);
    expect(proposal.reconciledTotal, 85);
    expect(proposal.reconcilesObservedTotal(), isTrue);
    expect(proposal.requiresUserReview, isTrue);
    expect(proposal.canCreateFormalRecord, isFalse);
    expect(proposal.lines.first.rawEvidence, '牛奶 2 x 30');
  });

  test('invalid numeric evidence fails closed instead of being inferred', () {
    const source = ProductRecognitionCandidate(
      totalAmount: 50,
      warnings: <String>['multiple_products_visible'],
    );

    final proposal = assembler.assemble(
      sourceCandidate: source,
      rawLines: <Map<String, Object?>>[
        <String, Object?>{
          'name': '商品A',
          'quantity': 0,
          'unitPrice': -1,
          'subtotal': double.nan,
          'rawEvidence': '商品A',
        },
      ],
    );

    expect(proposal.lines.single.quantity, isNull);
    expect(proposal.lines.single.unitPrice, isNull);
    expect(proposal.lines.single.subtotal, isNull);
    expect(proposal.hasAmbiguousLines, isTrue);
    expect(proposal.reconciledTotal, isNull);
    expect(proposal.reconcilesObservedTotal(), isFalse);
    expect(proposal.canCreateFormalRecord, isFalse);
  });

  test('empty evidence remains review-only and cannot synthesize a line', () {
    const source = ProductRecognitionCandidate(productName: '既有單品候選');

    final proposal = assembler.assemble(
      sourceCandidate: source,
      rawLines: const <Map<String, Object?>>[],
    );

    expect(proposal.lines, isEmpty);
    expect(proposal.reconciledTotal, isNull);
    expect(proposal.requiresUserReview, isTrue);
    expect(proposal.canCreateFormalRecord, isFalse);
  });
}
