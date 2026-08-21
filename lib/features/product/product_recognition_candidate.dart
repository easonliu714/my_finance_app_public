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

  bool get hasMultipleProducts => warnings.contains('multiple_products_visible');

  List<String> get displayWarningsZh => List<String>.unmodifiable(
        warnings.map(_warningDisplayZh),
      );

  ProductRecognitionAmountSource get resolvedAmountSource {
    if (totalAmount != null) return ProductRecognitionAmountSource.observedTotal;
    if (!hasMultipleProducts && quantity != null && unitPrice != null) {
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
        'hasMultipleProducts': hasMultipleProducts,
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
      ..._stringList(json['warnings']).map(_normalizeWarning),
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

  static const Set<String> _knownWarningCodes = <String>{
    'multiple_products_visible',
    'image_unclear',
    'occlusion_present',
    'price_not_visible',
    'price_ambiguous',
    'quantity_needs_review',
    'unit_price_needs_review',
    'merchant_needs_review',
    'merchant_brand_ambiguous',
    'quantity_invalid_or_non_positive',
    'unit_price_invalid_or_negative',
    'total_amount_invalid_or_negative',
    'other_review_required',
  };

  static String _normalizeWarning(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'other_review_required';
    final lower = normalized.toLowerCase().replaceAll('-', '_');
    if (_knownWarningCodes.contains(lower)) return lower;

    final mentionsMultiple = lower.contains('multiple') ||
        lower.contains('multi item') ||
        lower.contains('multi-item') ||
        normalized.contains('多項') ||
        normalized.contains('多個商品') ||
        normalized.contains('多件商品');
    if (mentionsMultiple) return 'multiple_products_visible';

    if ((lower.contains('unit') && lower.contains('price')) ||
        normalized.contains('單價')) {
      return 'unit_price_needs_review';
    }
    if (lower.contains('quantity') || normalized.contains('數量')) {
      return 'quantity_needs_review';
    }
    if (lower.contains('price') ||
        lower.contains('amount') ||
        normalized.contains('價格') ||
        normalized.contains('金額')) {
      return 'price_ambiguous';
    }
    if (lower.contains('occlud') ||
        normalized.contains('遮擋') ||
        normalized.contains('遮住')) {
      return 'occlusion_present';
    }
    if ((lower.contains('brand') && lower.contains('merchant')) ||
        (normalized.contains('品牌') && normalized.contains('商家'))) {
      return 'merchant_brand_ambiguous';
    }
    if (lower.contains('merchant') || normalized.contains('商家')) {
      return 'merchant_needs_review';
    }
    if (lower.contains('unclear') ||
        lower.contains('blur') ||
        normalized.contains('模糊') ||
        normalized.contains('不清楚')) {
      return 'image_unclear';
    }
    return 'other_review_required';
  }

  static String _warningDisplayZh(String code) => switch (code) {
        'multiple_products_visible' =>
          '辨識到多項商品；未可靠對應各品項單價，本次請以實際支付總金額覆核。',
        'image_unclear' => '影像不夠清楚，請人工確認辨識內容。',
        'occlusion_present' => '部分商品或價格被遮擋，請人工確認。',
        'price_not_visible' => '影像中未可靠辨識價格，請人工確認實際支付金額。',
        'price_ambiguous' => '價格證據不明確，請人工確認實際支付金額。',
        'quantity_needs_review' => '商品數量需要人工確認。',
        'unit_price_needs_review' => '單價無法可靠確認，請人工覆核。',
        'merchant_needs_review' => '消費商家需要人工確認。',
        'merchant_brand_ambiguous' => '商品品牌與消費商家可能不同，請人工確認。',
        'quantity_invalid_or_non_positive' => '辨識數量格式不正確，已保持空白。',
        'unit_price_invalid_or_negative' => '辨識單價格式不正確，已保持空白。',
        'total_amount_invalid_or_negative' => '辨識總金額格式不正確，已保持空白。',
        _ => 'AI 辨識結果有欄位需要人工確認。',
      };

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
