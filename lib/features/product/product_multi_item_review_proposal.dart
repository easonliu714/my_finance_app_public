import 'product_recognition_candidate.dart';

class ProductReviewLineProposal {
  const ProductReviewLineProposal({
    required this.name,
    this.quantity,
    this.unitPrice,
    this.subtotal,
    this.rawEvidence = '',
  });

  final String name;
  final double? quantity;
  final double? unitPrice;
  final double? subtotal;
  final String rawEvidence;

  bool get hasCompleteCalculation =>
      quantity != null && unitPrice != null && subtotal != null;

  double? get calculatedSubtotal =>
      quantity != null && unitPrice != null ? quantity! * unitPrice! : null;

  bool get subtotalReconciles {
    final calculated = calculatedSubtotal;
    if (calculated == null || subtotal == null) return false;
    return (calculated - subtotal!).abs() <= 0.01;
  }
}

class ProductMultiItemReviewProposal {
  const ProductMultiItemReviewProposal({
    required this.lines,
    required this.sourceCandidate,
  });

  final List<ProductReviewLineProposal> lines;
  final ProductRecognitionCandidate sourceCandidate;

  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;

  bool get isMultiItem => lines.length > 1;

  bool get hasAmbiguousLines => lines.any(
        (line) =>
            line.name.trim().isEmpty ||
            !line.hasCompleteCalculation ||
            !line.subtotalReconciles,
      );

  double? get reconciledTotal {
    if (lines.isEmpty || hasAmbiguousLines) return null;
    return lines.fold<double>(0, (sum, line) => sum + line.subtotal!);
  }

  bool reconcilesObservedTotal({double tolerance = 0.01}) {
    final observed = sourceCandidate.totalAmount;
    final calculated = reconciledTotal;
    if (observed == null || calculated == null) return false;
    return (observed - calculated).abs() <= tolerance;
  }
}
