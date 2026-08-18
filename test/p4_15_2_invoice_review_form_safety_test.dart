import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_card.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_review_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_review_submission_gate.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  const presenter = InvoiceReviewFormPresenter();
  const handoffPresenter = InvoiceReviewHandoffPresenter();

  test('editing and disclaimer acknowledgement enable safe review only', () {
    final state = handoffPresenter.fromAutomaticResult(
      InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
        message: 'OCR ready',
        selectedRouteReason: 'OCR selected',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        ocrResult: TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.success,
          message: 'OCR ready',
          candidate: TraditionalInvoiceOcrReviewCandidate(
            sourceImageReference: '/tmp/ready.jpg',
            invoiceNumber: '',
            sellerTaxId: '30340553',
            sellerTaxIdSource: 'test_fixture',
            invoiceDate: DateTime.utc(2026, 7, 6),
            sellerName: '',
            totalAmount: 100,
            visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
            confidence: const <TraditionalInvoiceOcrField,
                TraditionalInvoiceOcrConfidence>{},
            fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
          ),
        ),
      ),
    );

    final initial = presenter.fromHandoff(state);
    final edited = initial
        .updateField(InvoiceReviewFieldKey.invoiceNumber, ' AB87654321 ')
        .updateField(InvoiceReviewFieldKey.sellerName, ' Edited merchant ')
        .acknowledgeDisclaimer(true);

    expect(initial.canSubmitForReview, isFalse);
    expect(initial.requiredFieldsComplete, isFalse);
    expect(initial.missingRequiredFieldCount, 1);
    expect(initial.canSubmitReviewSafely, isFalse);
    expect(
      edited.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.value,
      'AB87654321',
    );
    expect(edited.canSubmitReviewSafely, isTrue);
    expect(edited.canCreateFormalRecord, isFalse);
  });

  test('manual designation and retry states cannot open review form', () {
    final manual = presenter.fromHandoff(
      handoffPresenter.fromAutomaticResult(
        const InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.manualQrDesignation,
          message: 'Manual QR',
          selectedRouteReason: 'QR ambiguous',
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        ),
      ),
    );
    final retry = presenter.fromHandoff(
      handoffPresenter.fromAutomaticResult(
        const InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.recognitionFailed,
          message: 'Failed',
          selectedRouteReason: 'Recognition failed',
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        ),
      ),
    );

    expect(manual.canOpenReview, isFalse);
    expect(manual.canSubmitReviewSafely, isFalse);
    expect(retry.canOpenReview, isFalse);
    expect(retry.canSubmitReviewSafely, isFalse);
  });

  test('safe submission summary exposes counts and flags only', () {
    const model = InvoiceReviewFormViewModel(
      title: 'Review',
      routeReason: 'route detail',
      disclaimer: invoiceRecognitionDisclaimer,
      fields: <InvoiceReviewFieldViewModel>[
        InvoiceReviewFieldViewModel(
          key: InvoiceReviewFieldKey.invoiceNumber,
          label: 'Invoice number',
          value: 'AB12345678',
          editable: true,
          requiredForReview: true,
        ),
      ],
      lineItems: <InvoiceReviewLineItemViewModel>[
        InvoiceReviewLineItemViewModel(
          name: 'SensitiveProductName',
          amountText: '999',
        ),
      ],
      warnings: <String>['Warning detail'],
      availableOverrides: <InvoiceReviewRouteOverride>[],
      canOpenReview: true,
      requiresAcknowledgement: true,
      disclaimerAcknowledged: false,
    );

    final safeText = model.toSafeSubmissionSummary().toString();

    expect(safeText, contains('fieldCount: 1'));
    expect(safeText, contains('missingRequiredFieldCount: 0'));
    expect(safeText, contains('canCreateFormalRecord: false'));
    expect(safeText, isNot(contains('AB12345678')));
    expect(safeText, isNot(contains('SensitiveProductName')));
    expect(safeText, isNot(contains('Warning detail')));
    expect(safeText, isNot(contains('route detail')));
  });

  testWidgets('review card gates continue action', (tester) async {
    InvoiceReviewFormViewModel? continued;
    final model = _cardModel(invoiceNumber: '');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InvoiceReviewFormCard(
              initialModel: model,
              onContinue: (value) => continued = value,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(InvoiceReviewFormCard.missingKey), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.byKey(InvoiceReviewFormCard.continueKey),
      ).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(
        InvoiceReviewFormCard.fieldKey(InvoiceReviewFieldKey.invoiceNumber),
      ),
      ' AB12345678 ',
    );
    await tester.tap(find.byKey(InvoiceReviewFormCard.acknowledgementKey));
    await tester.pump();
    await tester.tap(find.byKey(InvoiceReviewFormCard.continueKey));
    await tester.pump();

    expect(continued, isNotNull);
    expect(
      continued!.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.value,
      'AB12345678',
    );
    expect(continued!.canSubmitReviewSafely, isTrue);
    expect(continued!.canCreateFormalRecord, isFalse);
  });

  testWidgets('blocked result has no editable review form', (tester) async {
    const blocked = InvoiceReviewFormViewModel(
      title: 'Retry',
      routeReason: 'Unavailable',
      disclaimer: invoiceRecognitionDisclaimer,
      fields: <InvoiceReviewFieldViewModel>[],
      lineItems: <InvoiceReviewLineItemViewModel>[],
      warnings: <String>[],
      availableOverrides: <InvoiceReviewRouteOverride>[],
      canOpenReview: false,
      requiresAcknowledgement: false,
      disclaimerAcknowledged: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InvoiceReviewFormCard(initialModel: blocked)),
      ),
    );

    expect(find.byKey(InvoiceReviewFormCard.blockedKey), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(InvoiceReviewFormCard.continueKey), findsNothing);
  });
}

InvoiceReviewFormViewModel _cardModel({required String invoiceNumber}) {
  return InvoiceReviewFormViewModel(
    title: 'Review',
    routeReason: 'Local OCR',
    disclaimer: invoiceRecognitionDisclaimer,
    fields: <InvoiceReviewFieldViewModel>[
      InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceNumber,
        label: 'Invoice number',
        value: invoiceNumber,
        editable: true,
        requiredForReview: true,
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.invoiceDate,
        label: 'Invoice date',
        value: '2026-07-06',
        editable: true,
        requiredForReview: true,
      ),
      const InvoiceReviewFieldViewModel(
        key: InvoiceReviewFieldKey.totalAmount,
        label: 'Total',
        value: '100',
        editable: true,
        requiredForReview: true,
      ),
    ],
    lineItems: const <InvoiceReviewLineItemViewModel>[],
    warnings: const <String>[],
    availableOverrides: const <InvoiceReviewRouteOverride>[],
    canOpenReview: true,
    requiresAcknowledgement: true,
    disclaimerAcknowledged: false,
  );
}
