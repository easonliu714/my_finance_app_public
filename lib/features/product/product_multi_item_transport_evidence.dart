import 'product_multi_item_proposal_assembler.dart';
import 'product_multi_item_review_proposal.dart';
import 'product_recognition_candidate.dart';

/// Optional structured multi-item evidence carried by recognition transports.
///
/// The transport evidence is deliberately separate from the legacy
/// [ProductRecognitionCandidate]. Missing `lines` therefore leaves the existing
/// single-item contract unchanged. Structured rows remain review-only evidence
/// and never gain formal-write authority here.
class ProductMultiItemTransportEvidence {
  const ProductMultiItemTransportEvidence._(this.rawLines);

  final List<Map<String, Object?>> rawLines;

  static ProductMultiItemTransportEvidence? fromCandidateJson(
    Map<String, Object?> candidateJson,
  ) {
    if (!candidateJson.containsKey('lines')) return null;
    final encoded = candidateJson['lines'];
    if (encoded is! List) {
      return const ProductMultiItemTransportEvidence._(
        <Map<String, Object?>>[],
      );
    }

    final rows = <Map<String, Object?>>[];
    for (final encodedRow in encoded) {
      if (encodedRow is! Map) {
        rows.add(const <String, Object?>{});
        continue;
      }
      rows.add(<String, Object?>{
        'name': encodedRow['name'],
        'quantity': encodedRow['quantity'],
        'unitPrice': encodedRow['unitPrice'],
        'subtotal': encodedRow['subtotal'],
        'rawEvidence': encodedRow['rawEvidence'],
      });
    }
    return ProductMultiItemTransportEvidence._(
      List<Map<String, Object?>>.unmodifiable(rows),
    );
  }

  ProductMultiItemReviewProposal assembleReviewProposal({
    required ProductRecognitionCandidate sourceCandidate,
    ProductMultiItemProposalAssembler assembler =
        const ProductMultiItemProposalAssembler(),
  }) {
    return assembler.assemble(
      sourceCandidate: sourceCandidate,
      rawLines: rawLines,
    );
  }
}
