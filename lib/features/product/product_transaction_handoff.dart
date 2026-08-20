import 'product_recognition_candidate.dart';

enum ProductReviewTotalMode { automatic, manualOverride }

class ProductTransactionDraftSeed {
  const ProductTransactionDraftSeed({
    this.productName = '',
    this.quantity,
    this.unitPrice,
    this.amount,
    this.totalMode = ProductReviewTotalMode.automatic,
    this.category = '',
    this.merchant = '',
    this.accountName = '',
    this.note = '',
    this.reviewedByUser = false,
  });

  final String productName;
  final double? quantity;
  final double? unitPrice;
  final double? amount;
  final ProductReviewTotalMode totalMode;
  final String category;
  final String merchant;
  final String accountName;
  final String note;
  final bool reviewedByUser;

  // P4.19.2 compatibility aliases. P4.19.3 promotes these values from
  // suggestions into reviewed transaction-draft fields, but older callers and
  // regression tests still use the original names.
  String get categorySuggestion => category;
  String get merchantSuggestion => merchant;

  bool get requiresUserReview => !reviewedByUser;
  bool get canCreateFormalRecord => false;
  bool get isReadyForTransactionEntry =>
      reviewedByUser &&
      amount != null &&
      amount! > 0 &&
      category.trim().isNotEmpty &&
      accountName.trim().isNotEmpty;

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
    if (candidate.warnings.isNotEmpty) {
      noteParts.add('AI 警告：${candidate.warnings.join('；')}');
    }

    final canAutoCalculate = candidate.quantity != null &&
        candidate.quantity! > 0 &&
        candidate.unitPrice != null &&
        candidate.unitPrice! >= 0;
    if (canAutoCalculate) {
      noteParts.add('總額來源：數量×單價推導');
    }

    return ProductTransactionDraftSeed(
      productName: candidate.productName,
      quantity: candidate.quantity,
      unitPrice: candidate.unitPrice,
      amount: canAutoCalculate
          ? candidate.quantity! * candidate.unitPrice!
          : candidate.totalAmount,
      totalMode: canAutoCalculate
          ? ProductReviewTotalMode.automatic
          : ProductReviewTotalMode.manualOverride,
      category: candidate.categorySuggestion,
      merchant: candidate.merchantName,
      note: noteParts.join('\n'),
    );
  }

  ProductTransactionDraftSeed copyWith({
    String? productName,
    double? quantity,
    double? unitPrice,
    double? amount,
    bool clearAmount = false,
    ProductReviewTotalMode? totalMode,
    String? category,
    String? merchant,
    String? accountName,
    String? note,
    bool? reviewedByUser,
  }) {
    return ProductTransactionDraftSeed(
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      amount: clearAmount ? null : amount ?? this.amount,
      totalMode: totalMode ?? this.totalMode,
      category: category ?? this.category,
      merchant: merchant ?? this.merchant,
      accountName: accountName ?? this.accountName,
      note: note ?? this.note,
      reviewedByUser: reviewedByUser ?? this.reviewedByUser,
    );
  }

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'productName': productName,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'amount': amount,
        'totalMode': totalMode.name,
        'category': category,
        'merchant': merchant,
        'accountName': accountName,
        'note': note,
        'reviewedByUser': reviewedByUser,
        'requiresUserReview': requiresUserReview,
        'isReadyForTransactionEntry': isReadyForTransactionEntry,
        'canCreateFormalRecord': canCreateFormalRecord,
      };

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }
}
