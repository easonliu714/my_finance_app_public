import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_request_contract.dart';

void main() {
  test('adds optional lines without mutating legacy response schema', () {
    final legacyProperties = <String, Object?>{
      'productName': <String, Object?>{'type': <String>['string', 'null']},
    };
    final legacySchema = <String, Object?>{
      'type': 'object',
      'properties': legacyProperties,
      'required': <String>['productName'],
    };

    final wired = GeminiProductRecognitionRequestContract.responseSchema(
      legacySchema,
    );
    final wiredProperties = wired['properties']! as Map<String, Object?>;

    expect(wiredProperties['productName'], same(legacyProperties['productName']));
    expect(wiredProperties.containsKey('lines'), isTrue);
    expect(legacyProperties.containsKey('lines'), isFalse);
    expect(wired['required'], same(legacySchema['required']));
  });

  test('appends review-only multi-item instructions after legacy prompt', () {
    const legacy = 'LEGACY_SINGLE_ITEM_INSTRUCTIONS';
    final wired = GeminiProductRecognitionRequestContract.prompt(legacy);

    expect(wired, startsWith(legacy));
    expect(wired, contains('待人工覆核證據'));
    expect(wired, contains('不得自行用 quantity × unitPrice 補值'));
    expect(wired, contains('不得因此建立交易、商家、分類或其他 master data'));
  });

  test('malformed legacy properties fail closed without inventing properties', () {
    final legacySchema = <String, Object?>{
      'type': 'object',
      'properties': 'invalid',
      'required': <String>['productName'],
    };

    final wired = GeminiProductRecognitionRequestContract.responseSchema(
      legacySchema,
    );

    expect(wired, equals(legacySchema));
    expect(wired['properties'], 'invalid');
  });
}
