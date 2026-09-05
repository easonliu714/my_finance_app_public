import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_review_card.dart';

void main() {
  testWidgets('authority provenance becomes visible and explicit confirmation unlocks handoff', (
    tester,
  ) async {
    InvoiceTransactionHandoffDraft? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(),
              onOpenDraft: (draft) => opened = draft,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('權威：QR 原始資料'),
      findsNWidgets(3),
    );
    expect(
      find.text('權威：本機 OCR 補充（待人工確認）'),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey),
    );
    await tester.tap(
      find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey),
    );
    await tester.pump();

    expect(find.text('權威：已人工確認'), findsOneWidget);
    expect(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
    );
    await tester.tap(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
    );
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.canOpenTransactionDraft, isTrue);
    expect(opened!.canSaveFormalTransaction, isFalse);
  });

  testWidgets('missing non-required core field is blocked by authority gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(time: ''),
              onOpenDraft: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey),
    );
    await tester.tap(
      find.byKey(InvoiceTransactionHandoffReviewCard.confirmKey),
    );
    await tester.pump();

    expect(
      find.text('交易時間 缺少可確認的來源證據。'),
      findsOneWidget,
    );
    expect(
      find.byKey(InvoiceTransactionHandoffReviewCard.handoffKey),
      findsNothing,
    );
  });
}

InvoiceReviewFormViewModel _review({String time = '20:18'}) {
  return InvoiceReviewFormViewModel(
    title: '發票人工覆核',
    routeReason: 'runtime authority widget test',
    disclaimer: 'test',
    fields: <InvoiceReviewFieldViewModel>[
      _field(
        InvoiceReviewFieldKey.invoiceNumber,
        '發票號碼',
        'AB12345678',
        'QR 解析',
        required: true,
      ),
      _field(
        InvoiceReviewFieldKey.invoiceDate,
        '發票日期',
        '2026-08-24',
        'QR 解析',
        required: true,
      ),
      _field(
        InvoiceReviewFieldKey.invoiceTime,
        '交易時間',
        time,
        time.isEmpty ? '未辨識' : '本機 OCR 補充',
      ),
      _field(
        InvoiceReviewFieldKey.totalAmount,
        '總金額',
        '72',
        'QR 解析',
        required: true,
      ),
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
  String confidence, {
  bool required = false,
}) {
  return InvoiceReviewFieldViewModel(
    key: key,
    label: label,
    value: value,
    editable: true,
    requiredForReview: required,
    confidenceLabel: confidence,
  );
}
