import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_manual_review_card.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_review_calculator.dart';
import 'package:my_finance_app/features/product/product_transaction_handoff.dart';

void main() {
  testWidgets('calculator expression is button-only and never requests IME focus',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showProductReviewCalculator(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('product_review_calculator_expression')),
    );
    expect(field.readOnly, isTrue);
    expect(field.canRequestFocus, isFalse);
    expect(field.enableInteractiveSelection, isFalse);

    await tester.tap(find.widgetWithText(OutlinedButton, '4'));
    await tester.tap(find.widgetWithText(OutlinedButton, '+'));
    await tester.tap(find.widgetWithText(OutlinedButton, '5'));
    await tester.pump();
    expect(find.text('結果：9'), findsOneWidget);
  });

  testWidgets('restore auto is enabled even before quantity and unit price are valid',
      (tester) async {
    const candidate = ProductRecognitionCandidate(
      productName: '飲料',
      totalAmount: 17,
      categorySuggestion: '飲料水果',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductManualReviewCard(
              candidate: candidate,
              categoryOptions: const <String>['飲料水果'],
              merchantOptions: const <String>['不使用商家'],
              accountOptions: const <String>['一卡通'],
              onReviewed: (_) {},
            ),
          ),
        ),
      ),
    );

    final restoreFinder = find.byKey(ProductManualReviewCard.restoreAutoTotalKey);
    final restoreButton = tester.widget<TextButton>(restoreFinder);
    expect(restoreButton.onPressed, isNotNull);

    await tester.ensureVisible(restoreFinder);
    await tester.tap(restoreFinder);
    await tester.pump();

    var totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '');

    await tester.enterText(
      find.byKey(ProductManualReviewCard.quantityFieldKey),
      '2',
    );
    await tester.enterText(
      find.byKey(ProductManualReviewCard.unitPriceFieldKey),
      '20',
    );
    await tester.pump();

    totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '40');
  });

  testWidgets('multi-product explicit restore may use user-entered shared unit price',
      (tester) async {
    ProductTransactionDraftSeed? reviewed;
    const candidate = ProductRecognitionCandidate(
      productName: '飲料、點心',
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
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(ProductManualReviewCard.unitPriceFieldKey), findsNothing);
    final restoreFinder = find.byKey(ProductManualReviewCard.restoreAutoTotalKey);
    expect(tester.widget<TextButton>(restoreFinder).onPressed, isNotNull);

    await tester.ensureVisible(restoreFinder);
    await tester.tap(restoreFinder);
    await tester.pump();

    expect(find.byKey(ProductManualReviewCard.unitPriceFieldKey), findsOneWidget);
    expect(find.text('共同單價（人工）'), findsOneWidget);

    await tester.enterText(
      find.byKey(ProductManualReviewCard.unitPriceFieldKey),
      '30',
    );
    await tester.pump();

    final totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '60');

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

    expect(reviewed?.quantity, 2);
    expect(reviewed?.unitPrice, 30);
    expect(reviewed?.amount, 60);
    expect(reviewed?.totalMode, ProductReviewTotalMode.automatic);
    expect(reviewed?.note, contains('人工指定共同單價'));
  });
}
