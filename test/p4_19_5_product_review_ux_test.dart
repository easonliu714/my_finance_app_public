import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_manual_review_card.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_review_calculator.dart';
import 'package:my_finance_app/features/product/product_transaction_handoff.dart';

void main() {
  test('mixed-language multi-product warning becomes controlled zh-TW copy', () {
    final candidate = ProductRecognitionCandidate.fromJson(
      <String, Object?>{
        'productName': 'Black Tea + Toast',
        'quantity': 2,
        'unitPrice': 20,
        'warnings': <String>[
          'AI detected multiple products, unit price needs manual review',
        ],
      },
    );

    expect(candidate.hasMultipleProducts, isTrue);
    expect(candidate.warnings, <String>['multiple_products_visible']);
    expect(candidate.displayWarningsZh.single, contains('辨識到多項商品'));
    expect(candidate.displayWarningsZh.single, isNot(contains('multiple products')));
    expect(candidate.resolvedTotalAmount, isNull);
    expect(candidate.resolvedAmountSource, ProductRecognitionAmountSource.none);
  });

  test('multi-product accepts observed total but never derives aggregate unit price', () {
    const candidate = ProductRecognitionCandidate(
      productName: '飲料、吐司',
      quantity: 2,
      unitPrice: 36,
      totalAmount: 72,
      warnings: <String>['multiple_products_visible'],
    );

    expect(candidate.hasMultipleProducts, isTrue);
    expect(candidate.resolvedTotalAmount, 72);
    expect(
      candidate.resolvedAmountSource,
      ProductRecognitionAmountSource.observedTotal,
    );

    final seed = ProductTransactionDraftSeed.fromCandidate(candidate);
    expect(seed.amount, 72);
    expect(seed.unitPrice, isNull);
    expect(seed.totalMode, ProductReviewTotalMode.manualOverride);
    expect(seed.note, contains('多商品辨識總額'));
    expect(seed.note, isNot(contains('單價：36')));
    expect(seed.note, isNot(contains('數量×單價推導')));
  });

  test('calculator supports subtotal discount and safe invalid expressions', () {
    expect(
      ProductReviewCalculator.evaluateExpression('(45 + 27) × 0.9'),
      closeTo(64.8, 0.000001),
    );
    expect(ProductReviewCalculator.evaluateExpression('100 - 20'), 80);
    expect(ProductReviewCalculator.evaluateExpression('72 ÷ 0'), isNull);
    expect(ProductReviewCalculator.evaluateExpression('45 +'), isNull);
  });

  testWidgets('multi-product review hides misleading single unit-price field',
      (tester) async {
    const candidate = ProductRecognitionCandidate(
      productName: '大熱拿、花生吐司',
      quantity: 2,
      unitPrice: 36,
      totalAmount: 72,
      categorySuggestion: '飲料水果',
      merchantName: 'OK便利商店',
      warnings: <String>['multiple_products_visible'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductManualReviewCard(
              candidate: candidate,
              categoryOptions: const <String>['飲料水果'],
              merchantOptions: const <String>['不使用商家', 'OK便利商店'],
              accountOptions: const <String>['一卡通'],
              onReviewed: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(ProductManualReviewCard.multiProductTotalModeKey),
      findsOneWidget,
    );
    expect(find.byKey(ProductManualReviewCard.unitPriceFieldKey), findsNothing);
    expect(find.textContaining('未可靠對應各品項單價'), findsWidgets);
    expect(find.textContaining('multiple_products_visible'), findsNothing);

    final totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '72');
  });

  testWidgets('calculator apply invalidates confirmed review and updates paid total',
      (tester) async {
    ProductTransactionDraftSeed? reviewed;
    var invalidated = 0;
    const candidate = ProductRecognitionCandidate(
      productName: '大熱拿、花生吐司',
      quantity: 2,
      totalAmount: 72,
      categorySuggestion: '飲料水果',
      merchantName: 'OK便利商店',
      warnings: <String>['multiple_products_visible'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductManualReviewCard(
              candidate: candidate,
              categoryOptions: const <String>['飲料水果'],
              merchantOptions: const <String>['不使用商家', 'OK便利商店'],
              accountOptions: const <String>['一卡通'],
              onReviewed: (value) => reviewed = value,
              onReviewInvalidated: () => invalidated += 1,
            ),
          ),
        ),
      ),
    );

    final account = find.byKey(ProductManualReviewCard.accountFieldKey);
    await tester.ensureVisible(account);
    await tester.tap(account);
    await tester.pumpAndSettle();
    await tester.tap(find.text('一卡通').last);
    await tester.pumpAndSettle();

    final confirm = find.byKey(ProductManualReviewCard.confirmKey);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(reviewed?.amount, 72);
    expect(reviewed?.reviewedByUser, isTrue);

    final calculator = find.byKey(ProductManualReviewCard.calculatorKey);
    await tester.ensureVisible(calculator);
    await tester.tap(calculator);
    await tester.pumpAndSettle();

    final expressionFinder =
        find.byKey(const Key('product_review_calculator_expression'));
    final expressionField = tester.widget<TextField>(expressionFinder);
    expect(expressionField.readOnly, isTrue);
    expect(expressionField.canRequestFocus, isFalse);

    await tester.tap(find.widgetWithText(OutlinedButton, 'C'));
    await tester.pump();
    for (final keyText in <String>[
      '(', '4', '5', '+', '2', '7', ')', '×', '0', '.', '9',
    ]) {
      await tester.tap(find.widgetWithText(OutlinedButton, keyText));
      await tester.pump();
    }
    expect(find.text('結果：64.8'), findsOneWidget);

    await tester.tap(find.byKey(const Key('product_review_calculator_apply')));
    await tester.pumpAndSettle();

    expect(invalidated, 1);
    final totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '64.8');
    expect(find.text('已確認人工覆核'), findsNothing);
  });
}
