import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_transaction_handoff.dart';

void main() {
  test('product candidate is always review-only', () {
    const candidate = ProductRecognitionCandidate(
      productName: '無糖綠茶',
      quantity: 2,
      unitPrice: 35,
      totalAmount: 70,
      categorySuggestion: '飲料水果',
      merchantName: '測試商店',
    );

    expect(candidate.requiresUserReview, isTrue);
    expect(candidate.canCreateFormalRecord, isFalse);
    expect(candidate.resolvedTotalAmount, 70);
    expect(
      candidate.resolvedAmountSource,
      ProductRecognitionAmountSource.observedTotal,
    );
  });

  test('amount derives only when quantity and unit price are both explicit', () {
    const complete = ProductRecognitionCandidate(quantity: 3, unitPrice: 20);
    const missingPrice = ProductRecognitionCandidate(quantity: 3);
    const missingQuantity = ProductRecognitionCandidate(unitPrice: 20);

    expect(complete.resolvedTotalAmount, 60);
    expect(
      complete.resolvedAmountSource,
      ProductRecognitionAmountSource.derivedQuantityTimesUnitPrice,
    );
    expect(missingPrice.resolvedTotalAmount, isNull);
    expect(missingQuantity.resolvedTotalAmount, isNull);
  });

  test('malformed or unsafe numeric values stay empty and create warnings', () {
    final candidate = ProductRecognitionCandidate.fromJson(
      <String, Object?>{
        'productName': '商品',
        'quantity': -1,
        'unitPrice': 'NaN',
        'totalAmount': -50,
        'warnings': <String>['image_unclear'],
      },
    );

    expect(candidate.quantity, isNull);
    expect(candidate.unitPrice, isNull);
    expect(candidate.totalAmount, isNull);
    expect(candidate.resolvedTotalAmount, isNull);
    expect(candidate.warnings, contains('image_unclear'));
    expect(candidate.warnings, contains('quantity_invalid_or_non_positive'));
    expect(candidate.warnings, contains('unit_price_invalid_or_negative'));
    expect(candidate.warnings, contains('total_amount_invalid_or_negative'));
  });

  test('confidence is clamped and unknown fields are ignored', () {
    final candidate = ProductRecognitionCandidate.fromJson(
      <String, Object?>{
        'confidence': <String, Object?>{
          'productName': 1.4,
          'quantity': -0.5,
          'merchantName': 0.75,
          'unknown': 1,
        },
      },
    );

    expect(candidate.confidence[ProductRecognitionField.productName], 1);
    expect(candidate.confidence[ProductRecognitionField.quantity], 0);
    expect(candidate.confidence[ProductRecognitionField.merchantName], 0.75);
    expect(candidate.confidence.length, 3);
  });

  test('handoff seed prefills candidate data but cannot write formally', () {
    const candidate = ProductRecognitionCandidate(
      productName: '茶飲',
      quantity: 2,
      unitPrice: 45,
      categorySuggestion: '飲料水果',
      merchantName: '一品親泡菜店',
      warnings: <String>['merchant_needs_review'],
    );

    final seed = ProductTransactionDraftSeed.fromCandidate(candidate);

    expect(seed.amount, 90);
    expect(seed.categorySuggestion, '飲料水果');
    expect(seed.merchantSuggestion, '一品親泡菜店');
    expect(seed.note, contains('商品：茶飲'));
    expect(seed.note, contains('數量：2'));
    expect(seed.note, contains('單價：45'));
    expect(seed.note, contains('數量×單價推導'));
    expect(seed.note, contains('消費商家需要人工確認'));
    expect(seed.note, isNot(contains('merchant_needs_review')));
    expect(seed.requiresUserReview, isTrue);
    expect(seed.canCreateFormalRecord, isFalse);
  });

  test('safe JSON contains no API credential fields', () {
    const candidate = ProductRecognitionCandidate(productName: '商品');
    final json = candidate.toSafeJson();

    expect(json.keys, isNot(contains('apiKey')));
    expect(json.keys, isNot(contains('api_key')));
    expect(json['canCreateFormalRecord'], isFalse);
  });
}
