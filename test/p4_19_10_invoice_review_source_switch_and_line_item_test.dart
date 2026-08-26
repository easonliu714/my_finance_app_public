import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_qr_parser.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_router.dart';
import 'package:my_finance_app/features/invoice/invoice_review_field_source_switch.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_review_qr_line_item_enricher.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_review_card.dart';

void main() {
  testWidgets('field pill switch explicitly adopts AI candidate', (tester) async {
    const ai = GeminiInvoiceReviewCandidate(
      invoiceNumber: 'CD87654321',
      invoicePeriod: '115年7-8月份',
      sellerTaxId: '12345675',
      invoiceDate: '2026-08-26',
      invoiceTime: '20:15',
      merchantName: 'AI 商家',
      totalAmount: 99,
      lineItems: <GeminiInvoiceReviewLineItem>[],
      confidence: <GeminiInvoiceReviewField, double>{},
      warnings: <String>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceTransactionHandoffReviewCard(
              initialReview: _review(),
              aiComparisonRequired: true,
              aiCandidate: ai,
              onOpenDraft: (_) {},
            ),
          ),
        ),
      ),
    );

    final source = find.byKey(
      InvoiceTransactionHandoffReviewCard.sourceSwitchKey(
        InvoiceReviewFieldKey.invoiceNumber,
      ),
    );
    expect(source, findsOneWidget);
    final aiButton = find.descendant(
      of: source,
      matching: find.byKey(const Key('invoice_source_switch_ai')),
    );
    await tester.tap(aiButton);
    await tester.pumpAndSettle();

    expect(find.text('CD87654321'), findsOneWidget);
    expect(find.text('權威：使用者明確採用 AI'), findsOneWidget);
  });

  test('right QR line items enrich review and handoff note', () {
    const left = InvoiceQrParseResult(
      rawPayload: 'left',
      invoiceNumber: 'AB12345678',
      errors: <String>[],
      warnings: <String>[],
    );
    const routing = InvoiceRecognitionRoutingResult(
      route: InvoiceRecognitionRoute.electronicInvoiceQr,
      message: 'paired',
      pairs: <InvoiceQrPairCandidate>[
        InvoiceQrPairCandidate(
          left: InvoiceQrPayloadEvidence(
            imageReference: 'image',
            fileName: 'invoice.jpg',
            rawPayload: 'left',
            role: InvoiceQrPayloadRole.left,
            leftParseResult: left,
          ),
          right: InvoiceQrPayloadEvidence(
            imageReference: 'image',
            fileName: 'invoice.jpg',
            rawPayload: '**茶:2:35:麵包:1:25',
            role: InvoiceQrPayloadRole.right,
          ),
        ),
      ],
    );
    const recognition = InvoiceAutomaticRecognitionResult(
      status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
      message: 'ok',
      selectedRouteReason: 'test',
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      qrResult: InvoiceLocalRecognitionResult(
        status: InvoiceLocalRecognitionStatus.qrCandidate,
        message: 'ok',
        failedImageReferences: <String>[],
        routingResult: routing,
      ),
    );

    final enriched = const InvoiceReviewQrLineItemEnricher().enrich(
      review: _review(),
      recognition: recognition,
    );
    expect(enriched.lineItems, hasLength(2));
    expect(enriched.lineItems.first.name, '茶');
    expect(enriched.lineItems.first.amountText, '70');

    final draft = const InvoiceTransactionHandoffContract().build(
      review: enriched,
      reviewConfirmed: true,
    );
    expect(draft.note, contains('品項明細：'));
    expect(draft.note, contains('- 茶：70'));
    expect(draft.note, contains('- 麵包：25'));
  });

  testWidgets('source switch renders manual state distinctly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InvoiceReviewFieldSourceSwitch(
          selection: InvoiceReviewFieldSourceSelection.manual,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.text('手動'), findsOneWidget);
    expect(find.text('OCR'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
  });
}

InvoiceReviewFormViewModel _review() {
  return InvoiceReviewFormViewModel(
    title: '發票覆核',
    routeReason: 'test',
    disclaimer: 'test',
    fields: <InvoiceReviewFieldViewModel>[
      _field(InvoiceReviewFieldKey.invoiceNumber, '發票號碼', 'AB12345678'),
      _field(InvoiceReviewFieldKey.invoiceDate, '發票日期', '2026-08-26'),
      _field(InvoiceReviewFieldKey.invoiceTime, '交易時間', '20:10'),
      _field(InvoiceReviewFieldKey.sellerTaxId, '賣方統編', '12345675'),
      _field(InvoiceReviewFieldKey.sellerName, '商家名稱', 'OCR 商家'),
      _field(InvoiceReviewFieldKey.totalAmount, '總金額', '70'),
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
    requiredForReview: key == InvoiceReviewFieldKey.invoiceNumber ||
        key == InvoiceReviewFieldKey.invoiceDate ||
        key == InvoiceReviewFieldKey.invoiceTime ||
        key == InvoiceReviewFieldKey.totalAmount,
    confidenceLabel: key == InvoiceReviewFieldKey.invoiceNumber ? '本機 OCR' : '本機 OCR',
  );
}
