import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_contract.dart';

void main() {
  const contract = InvoiceTransactionHandoffContract();

  test('confirmed invoice can open draft but formal master selections stay required', () {
    final draft = contract.build(
      review: _review(),
      reviewConfirmed: true,
    );

    expect(draft.amount, 72);
    expect(draft.occurredAt, DateTime(2026, 8, 24, 20, 18));
    expect(draft.recognizedMerchantCandidate, 'OK便利商店');
    expect(draft.formalMerchantName, isEmpty);
    expect(draft.formalAccountName, isEmpty);
    expect(draft.formalCategory, isEmpty);
    expect(draft.canOpenTransactionDraft, isTrue);
    expect(draft.canSaveFormalTransaction, isFalse);
    expect(draft.requiresExplicitMerchantSelection, isTrue);
    expect(draft.requiresExplicitAccountSelection, isTrue);
    expect(draft.requiresExplicitCategorySelection, isTrue);
    expect(draft.warnings, contains('FORMAL_MERCHANT_SELECTION_REQUIRED'));
    expect(draft.warnings, contains('FORMAL_ACCOUNT_SELECTION_REQUIRED'));
    expect(draft.warnings, contains('FORMAL_CATEGORY_SELECTION_REQUIRED'));
    expect(draft.note, contains('來源：發票辨識人工覆核'));
    expect(draft.note, contains('發票號碼：AB12345678'));
    expect(draft.note, contains('賣方統編：12345675'));
    expect(draft.note, contains('發票期別：115年7-8月份'));
    expect(draft.note, contains('隨機碼：2468'));
  });

  test('formal selections are separate authority from recognized merchant text', () {
    final draft = contract.build(
      review: _review(merchant: 'OCR 候選商家'),
      reviewConfirmed: true,
      formalMerchantName: 'OK便利商店',
      formalAccountName: '一卡通 Money',
      formalCategory: '早餐',
    );

    expect(draft.recognizedMerchantCandidate, 'OCR 候選商家');
    expect(draft.formalMerchantName, 'OK便利商店');
    expect(draft.formalAccountName, '一卡通 Money');
    expect(draft.formalCategory, '早餐');
    expect(draft.canSaveFormalTransaction, isTrue);
    expect(draft.warnings, isEmpty);
  });

  test('unconfirmed or invalid core invoice fields fail closed', () {
    final unconfirmed = contract.build(
      review: _review(),
      reviewConfirmed: false,
    );
    expect(unconfirmed.canOpenTransactionDraft, isFalse);
    expect(unconfirmed.warnings, contains('REVIEW_CONFIRMATION_REQUIRED'));

    final invalid = contract.build(
      review: _review(amount: '0', date: '2026-02-30', time: '25:00'),
      reviewConfirmed: true,
    );
    expect(invalid.amount, isNull);
    expect(invalid.occurredAt, isNull);
    expect(invalid.canOpenTransactionDraft, isFalse);
    expect(invalid.warnings, contains('TOTAL_AMOUNT_REQUIRED_OR_INVALID'));
    expect(invalid.warnings, contains('INVOICE_DATE_TIME_REQUIRED_OR_INVALID'));
  });

  test('handoff contract remains review-only and has no formal write dependency', () {
    final source = File(
      'lib/features/invoice/invoice_transaction_handoff_contract.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('TransactionStore')));
    expect(source, isNot(contains('transactionLedgerProvider')));
    expect(source, isNot(contains('upsertMerchant')));
    expect(source, isNot(contains('upsertAccount')));
    expect(source, isNot(contains('insertFormalTransaction')));
  });
}

InvoiceReviewFormViewModel _review({
  String merchant = 'OK便利商店',
  String amount = '72',
  String date = '2026-08-24',
  String time = '20:18',
}) {
  return InvoiceReviewFormViewModel(
    title: '發票人工覆核',
    routeReason: 'test',
    disclaimer: 'test',
    fields: <InvoiceReviewFieldViewModel>[
      _field(InvoiceReviewFieldKey.invoiceNumber, '發票號碼', 'AB12345678'),
      _field(InvoiceReviewFieldKey.invoiceDate, '發票日期', date),
      _field(InvoiceReviewFieldKey.invoiceTime, '交易時間', time),
      _field(InvoiceReviewFieldKey.sellerTaxId, '賣方統編', '12345675'),
      _field(InvoiceReviewFieldKey.sellerName, '商家名稱', merchant),
      _field(InvoiceReviewFieldKey.totalAmount, '總金額', amount),
      _field(InvoiceReviewFieldKey.invoicePeriod, '發票期別', '115年7-8月份'),
      _field(InvoiceReviewFieldKey.randomCode, '隨機碼', '2468'),
    ],
    lineItems: const <InvoiceReviewLineItemViewModel>[],
    warnings: const <String>[],
    availableOverrides: const [],
    canOpenReview: true,
    requiresAcknowledgement: false,
    disclaimerAcknowledged: true,
  );
}

InvoiceReviewFieldViewModel _field(
  InvoiceReviewFieldKey key,
  String label,
  String value,
) {
  return InvoiceReviewFieldViewModel(
    key: key,
    label: label,
    value: value,
    editable: true,
    requiredForReview: false,
  );
}
