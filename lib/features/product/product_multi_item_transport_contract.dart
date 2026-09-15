/// Recognition transport contract for optional structured multi-item evidence.
///
/// This contract deliberately does not change the legacy single-item candidate
/// authority. A transport may opt into `lines`; consumers must still route the
/// rows through ProductMultiItemTransportEvidence and the fail-closed assembler.
abstract final class ProductMultiItemTransportContract {
  static const String fieldName = 'lines';

  static const String promptAddendum = '''
10. lines：這是可選的多商品「待人工覆核證據」，不是多筆正式交易。只有畫面明確存在多個不同商品時才提供；否則可省略此欄位。
11. lines 每列只能填影像明確可見的 name、quantity、unitPrice、subtotal、rawEvidence。不確定或被遮住的值填 null；不得用常識、市價或其他列推測。
12. subtotal 只有影像明確顯示該列小計時才填；不得自行用 quantity × unitPrice 補值。App 端會獨立做 deterministic reconciliation。
13. rawEvidence 只保留支持該列商品、數量與價格的簡短可見文字。多列證據不得合併成單一虛構商品。
14. 即使 lines 完整，也只形成 review proposal；不得因此建立交易、商家、分類或其他 master data。
''';

  static const Map<String, Object?> responseSchemaProperty =
      <String, Object?>{
    'type': <String>['array', 'null'],
    'items': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'name': <String, Object?>{
          'type': <String>['string', 'null'],
        },
        'quantity': <String, Object?>{
          'type': <String>['number', 'null'],
        },
        'unitPrice': <String, Object?>{
          'type': <String>['number', 'null'],
        },
        'subtotal': <String, Object?>{
          'type': <String>['number', 'null'],
        },
        'rawEvidence': <String, Object?>{
          'type': <String>['string', 'null'],
        },
      },
      'required': <String>[
        'name',
        'quantity',
        'unitPrice',
        'subtotal',
        'rawEvidence',
      ],
    },
  };

  /// Returns a new properties map with the optional multi-item evidence field.
  /// The caller's legacy schema is never mutated, so existing single-item
  /// authority cannot be changed as a side effect of enabling this transport.
  static Map<String, Object?> withOptionalLinesProperty(
    Map<String, Object?> legacyProperties,
  ) {
    return <String, Object?>{
      ...legacyProperties,
      fieldName: responseSchemaProperty,
    };
  }

  /// Appends the frozen review-only instructions without rewriting the legacy
  /// prompt. This keeps multi-item transport additive and auditable.
  static String withPromptAddendum(String legacyPrompt) {
    return '$legacyPrompt\n$promptAddendum';
  }
}
