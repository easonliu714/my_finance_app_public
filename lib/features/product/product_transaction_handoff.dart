import 'product_recognition_candidate.dart';

class ProductTransactionDraftSeed {
  const ProductTransactionDraftSeed({
    this.amount,
    this.categorySuggestion = '',
    this.merchantSuggestion = '',
    this.note = '',
  });

  final double? amount;
  final String categorySuggestion;
  final String merchantSuggestion;
  final String note;

  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;

  factory ProductTransactionDraftSeed.fromCandidate(
    ProductRecognitionCandidate candidate,
  ) {
    final noteParts = <String>[];
    if (candidate.productName.isNotEmpty) {
      noteParts.add('商品：${candidate.productName}');
    }
    if (candidate.quantity != null) {
      noteParts.add('數量：${_number(candidate.quantity!)}');
    }
    if (candidate.unitPrice != null) {
      noteParts.add('單價：${_number(candidate.unitPrice!)}');
    }
    if (candidate.resolvedAmountSource ==
        ProductRecognitionAmountSource.derivedQuantityTimesUnitPrice) {
      noteParts.add('金額來源：數量×單價推導，需人工確認');
    }
    if (candidate.warnings.isNotEmpty) {
      noteParts.add('AI 警告：${candidate.warnings.join('；')}');
    }

    return ProductTransactionDraftSeed(
      amount: candidate.resolvedTotalAmount,
      categorySuggestion: candidate.categorySuggestion,
      merchantSuggestion: candidate.merchantName,
      note: noteParts.join('\n'),
    );
  }

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'amount': amount,
        'categorySuggestion': categorySuggestion,
        'merchantSuggestion': merchantSuggestion,
        'note': note,
        'requiresUserReview': requiresUserReview,
        'canCreateFormalRecord': canCreateFormalRecord,
      };

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }
}
