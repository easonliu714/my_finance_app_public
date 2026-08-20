import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_manual_review_card.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_transaction_handoff.dart';

void main() {
  Future<void> selectAccount(WidgetTester tester, String account) async {
    await tester.ensureVisible(find.byKey(ProductManualReviewCard.accountFieldKey));
    await tester.tap(find.byKey(ProductManualReviewCard.accountFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(account).last);
    await tester.pumpAndSettle();
  }

  test('reviewed draft is only ready after explicit formal selections', () {
    const candidate = ProductRecognitionCandidate(
      productName: '無糖綠茶',
      quantity: 2,
      unitPrice: 35,
      categorySuggestion: '飲料水果',
      merchantName: '測試商店',
    );

    final initial = ProductTransactionDraftSeed.fromCandidate(candidate);
    expect(initial.amount, 70);
    expect(initial.totalMode, ProductReviewTotalMode.automatic);
    expect(initial.requiresUserReview, isTrue);
    expect(initial.isReadyForTransactionEntry, isFalse);
    expect(initial.canCreateFormalRecord, isFalse);

    final reviewed = initial.copyWith(
      category: '飲料水果',
      merchant: '測試商店',
      accountName: '現金',
      reviewedByUser: true,
    );
    expect(reviewed.isReadyForTransactionEntry, isTrue);
    expect(reviewed.canCreateFormalRecord, isFalse);
    expect(reviewed.toSafeJson()['accountName'], '現金');
    expect(reviewed.toSafeJson().keys, isNot(contains('apiKey')));
  });

  testWidgets('automatic total uses quantity times unit price and requires account',
      (tester) async {
    ProductTransactionDraftSeed? reviewed;
    const candidate = ProductRecognitionCandidate(
      productName: '無糖綠茶',
      quantity: 2,
      unitPrice: 35,
      totalAmount: 99,
      categorySuggestion: '飲料水果',
      merchantName: '測試商店',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductManualReviewCard(
              candidate: candidate,
              categoryOptions: const <String>['飲料水果'],
              merchantOptions: const <String>['不使用商家', '測試商店'],
              accountOptions: const <String>['現金'],
              onReviewed: (value) => reviewed = value,
            ),
          ),
        ),
      ),
    );

    final totalField = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(totalField.controller?.text, '70');
    expect(find.textContaining('自動：數量 × 單價 = 70'), findsOneWidget);
    expect(find.textContaining('AI 辨識總額 99'), findsOneWidget);

    await tester.ensureVisible(find.byKey(ProductManualReviewCard.confirmKey));
    await tester.tap(find.byKey(ProductManualReviewCard.confirmKey));
    await tester.pump();
    expect(find.text('請選擇消費扣款帳戶'), findsOneWidget);
    expect(reviewed, isNull);

    await selectAccount(tester, '現金');
    await tester.ensureVisible(find.byKey(ProductManualReviewCard.confirmKey));
    await tester.tap(find.byKey(ProductManualReviewCard.confirmKey));
    await tester.pumpAndSettle();

    expect(reviewed, isNotNull);
    expect(reviewed!.amount, 70);
    expect(reviewed!.totalMode, ProductReviewTotalMode.automatic);
    expect(reviewed!.category, '飲料水果');
    expect(reviewed!.merchant, '測試商店');
    expect(reviewed!.accountName, '現金');
    expect(reviewed!.reviewedByUser, isTrue);
    expect(reviewed!.canCreateFormalRecord, isFalse);
  });

  testWidgets('manual total override is preserved in reviewed draft',
      (tester) async {
    ProductTransactionDraftSeed? reviewed;
    const candidate = ProductRecognitionCandidate(
      productName: '咖啡',
      quantity: 2,
      unitPrice: 50,
      categorySuggestion: '飲料水果',
      merchantName: '測試商店',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductManualReviewCard(
              candidate: candidate,
              categoryOptions: const <String>['飲料水果'],
              merchantOptions: const <String>['不使用商家', '測試商店'],
              accountOptions: const <String>['現金'],
              onReviewed: (value) => reviewed = value,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
      '120',
    );
    await tester.pump();
    expect(find.textContaining('人工修改模式'), findsOneWidget);
    await selectAccount(tester, '現金');
    await tester.ensureVisible(find.byKey(ProductManualReviewCard.confirmKey));
    await tester.tap(find.byKey(ProductManualReviewCard.confirmKey));
    await tester.pumpAndSettle();

    expect(reviewed, isNotNull);
    expect(reviewed!.amount, 120);
    expect(reviewed!.totalMode, ProductReviewTotalMode.manualOverride);
    expect(reviewed!.note, contains('總額來源：人工修改'));
  });

  test('product handoff cannot bypass the transaction Save boundary', () {
    final productPage = File(
      'lib/features/product/product_capture_page.dart',
    ).readAsStringSync();
    final transactionPage = File(
      'lib/features/transaction/transaction_entry_page.dart',
    ).readAsStringSync();

    expect(productPage, contains('TransactionEntrySeed('));
    expect(productPage, contains('context.pushNamed('));
    expect(productPage, isNot(contains('transactionLedgerProvider.notifier).add(')));
    expect(productPage, isNot(contains('transactionLedgerProvider.notifier).updateRecord(')));
    expect(transactionPage, contains('Future<void> _saveTransaction() async'));
    expect(transactionPage, contains('await _persistRecord(record);'));
    expect(transactionPage, contains('onSave: _saveTransaction'));
  });
}
