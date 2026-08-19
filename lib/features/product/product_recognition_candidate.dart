enum ProductRecognitionAmountSource {
  none,
  observedTotal,
  derivedQuantityTimesUnitPrice,
}

enum ProductRecognitionField {
  productName,
  quantity,
  unitPrice,
  totalAmount,
  categorySuggestion,
  merchantName,
}

class ProductRecognitionCandidate {
  const ProductRecognitionCandidate({
    this.productName = '',
    this.quantity,
    this.unitPrice,
    this.totalAmount,
    this.categorySuggestion = '',
    this.merchantName = '',
    this.recognizedText = '',
    this.confidence = const <ProductRecognitionField, double>{},
    this.warnings = const <String>[],
  });

  final String productName;
  final double? quantity;
  final double? unitPrice;
  final double? totalAmount;
  final String categorySuggestion;
  final String merchantName;
  final String recognizedText;
  final Map<ProductRecognitionField, double> confidence;
  final List<String> warnings;

  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;

  ProductRecognitionAmountSource get resolvedAmountSource {
    if (totalAmount != null) return ProductRecognitionAmountSource.observedTotal;
    if (quantity != null && unitPrice != null) {
      return ProductRecognitionAmountSource.derivedQuantityTimesUnitPrice;
    }
    return ProductRecognitionAmountSource.none;
  }

  double? get resolvedTotalAmount => switch (resolvedAmountSource) {
        ProductRecognitionAmountSource.observedTotal => totalAmount,
        ProductRecognitionAmountSource.derivedQuantityTimesUnitPrice =>
          quantity! * unitPrice!,
        ProductRecognitionAmountSource.none => null,
      };

  bool get hasUsefulCandidate =>
      productName.isNotEmpty ||
      resolvedTotalAmount != null ||
      categorySuggestion.isNotEmpty ||
      merchantName.isNotEmpty;

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'productName': productName,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalAmount': totalAmount,
        'resolvedTotalAmount': resolvedTotalAmount,
        'resolvedAmountSource': resolvedAmountSource.name,
        'categorySuggestion': categorySuggestion,
        'merchantName': merchantName,
        'recognizedText': recognizedText,
        'confidence': <String, double>{
          for (final entry in confidence.entries) entry.key.name: entry.value,
        },
        'warnings': warnings,
        'requiresUserReview': requiresUserReview,
        'canCreateFormalRecord': canCreateFormalRecord,
      };

  factory ProductRecognitionCandidate.fromJson(Map<String, Object?> json) {
    final warnings = <String>[
      ..._stringList(json['warnings']),
    ];

    final quantity = _positiveNumber(json['quantity']);
    if (json['quantity'] != null && quantity == null) {
      warnings.add('quantity_invalid_or_non_positive');
    }

    final unitPrice = _nonNegativeNumber(json['unitPrice']);
    if (json['unitPrice'] != null && unitPrice == null) {
      warnings.add('unit_price_invalid_or_negative');
    }

    final totalAmount = _nonNegativeNumber(json['totalAmount']);
    if (json['totalAmount'] != null && totalAmount == null) {
      warnings.add('total_amount_invalid_or_negative');
    }

    return ProductRecognitionCandidate(
      productName: _string(json['productName']),
      quantity: quantity,
      unitPrice: unitPrice,
      totalAmount: totalAmount,
      categorySuggestion: _string(json['categorySuggestion']),
      merchantName: _string(json['merchantName']),
      recognizedText: _string(json['recognizedText']),
      confidence: _confidence(json['confidence']),
      warnings: List<String>.unmodifiable(_deduplicate(warnings)),
    );
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static double? _positiveNumber(Object? value) {
    final parsed = _finiteNumber(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static double? _nonNegativeNumber(Object? value) {
    final parsed = _finiteNumber(value);
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static double? _finiteNumber(Object? value) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((entry) => entry?.toString().trim() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static Map<ProductRecognitionField, double> _confidence(Object? value) {
    if (value is! Map) return const <ProductRecognitionField, double>{};
    final result = <ProductRecognitionField, double>{};
    for (final field in ProductRecognitionField.values) {
      final raw = value[field.name];
      final parsed = _finiteNumber(raw);
      if (parsed == null) continue;
      result[field] = parsed.clamp(0, 1).toDouble();
    }
    return Map<ProductRecognitionField, double>.unmodifiable(result);
  }

  static List<String> _deduplicate(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty && seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }
}
