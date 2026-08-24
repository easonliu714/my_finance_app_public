import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_review_card.dart';

void main() {
  testWidgets('confirmed review opens draft and post-confirm edit invalidates handoff',
      (tester) async {
    InvoiceTransactionHandoffDraft? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(),
              onOpenDraft: (value) => opened = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey));
    await tester.pump();
    expect(find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey), findsOneWidget);

    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey));
    await tester.pump();
    expect(opened, isNotNull);
    expect(opened!.amount, 72);
    expect(opened!.idempotencyKey, 'invoice-review:AB12345678:20260824:12345675');

    await tester.enterText(
      find.byKey(
        InvoiceTransactionHandoffReviewCard.fieldKey(
          InvoiceReviewFieldKey.totalAmount,
        ),
      ),
      '80',
    );
    await tester.pump();

    expect(find.byKey(InvoiceTransactionHandoffReviewCard.reconfirmKey), findsOneWidget);
    expect(find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey), findsNothing);

    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey));
    await tester.pump();
    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey));
    await tester.pump();
    expect(opened!.amount, 80);
  });

  testWidgets('required local acknowledgement and AI comparison both gate confirmation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(requiresAcknowledgement: true),
              aiComparisonRequired: true,
              aiComparisonAcknowledged: false,
              onOpenDraft: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey));
    await tester.pump();
    expect(find.text('請先完成辨識覆核確認。'), findsOneWidget);

    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.disclaimerKey));
    await tester.pump();
    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey));
    await tester.pump();
    expect(find.text('請先核對本機與 AI 結果，再確認發票覆核。'), findsOneWidget);
    expect(find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey), findsNothing);
  });

  testWidgets('missing required invoice field stays fail closed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(invoiceNumber: ''),
              onOpenDraft: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey));
    await tester.pump();
    expect(find.textContaining('請先補齊必要欄位：發票號碼'), findsOneWidget);
    expect(find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey), findsNothing);
  });
}

InvoiceReviewFormViewModel _review({
  String invoiceNumber = 'AB12345678',
  bool requiresAcknowledgement = false,
}) {
  return InvoiceReviewFormViewModel(
    title: '發票人工覆核',
    routeReason: 'test',
    disclaimer: 'test',
    fields: <InvoiceReviewFieldViewModel>[
      _field(
        InvoiceReviewFieldKey.invoiceNumber,
        '發票號碼',
        invoiceNumber,
        required: true,
      ),
      _field(
        InvoiceReviewFieldKey.invoiceDate,
        '發票日期',
        '2026-08-24',
        required: true,
      ),
      _field(
        InvoiceReviewFieldKey.invoiceTime,
        '交易時間',
        '20:18',
        required: true,
      ),
      _field(
        InvoiceReviewFieldKey.sellerTaxId,
        '賣方統編',
        '12345675',
        required: true,
      ),
      _field(InvoiceReviewFieldKey.sellerName, '商家名稱', 'OK便利商店'),
      _field(
        InvoiceReviewFieldKey.totalAmount,
        '總金額',
        '72',
        required: true,
      ),
      _field(InvoiceReviewFieldKey.invoicePeriod, '發票期別', '115年7-8月份'),
      _field(InvoiceReviewFieldKey.randomCode, '隨機碼', '2468'),
    ],
    lineItems: const <InvoiceReviewLineItemViewModel>[],
    warnings: const <String>[],
    availableOverrides: const [],
    canOpenReview: true,
    requiresAcknowledgement: requiresAcknowledgement,
    disclaimerAcknowledged: !requiresAcknowledgement,
  );
}

InvoiceReviewFieldViewModel _field(
  InvoiceReviewFieldKey key,
  String label,
  String value, {
  bool required = false,
}) {
  return InvoiceReviewFieldViewModel(
    key: key,
    label: label,
    value: value,
    editable: true,
    requiredForReview: required,
  );
}
