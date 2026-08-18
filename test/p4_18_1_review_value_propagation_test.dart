import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_review_form_presenter.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_review_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  test('invoice period extraction canonicalizes equivalent ROC period text', () {
    expect(extractCanonicalInvoicePeriod('115年5-6月份'), '115年5-6月份');
    expect(extractCanonicalInvoicePeriod('中華民國 115年05-06月'), '115年5-6月份');
    expect(extractCanonicalInvoicePeriod('115年 05 ～ 06 月份'), '115年5-6月份');
    expect(normalizeInvoicePeriodForComparison('115年5-6月份'), '115-05-06');
    expect(normalizeInvoicePeriodForComparison('115年05-06月'), '115-05-06');
  });

  test('ambiguous or invalid invoice periods stay blank', () {
    expect(extractCanonicalInvoicePeriod('115年13-14月份'), '');
    expect(extractCanonicalInvoicePeriod('115年6-5月份'), '');
    expect(
      extractCanonicalInvoicePeriod('115年5-6月份 115年7-8月份'),
      '',
    );
  });

  // P4.18.2 regression: base Traditional Review must surface strict OCR time.
  test('traditional OCR base form propagates strict raw time into review field', () {
    final handoff = _xy17859005Handoff();
    final form = const InvoiceReviewFormPresenter().fromHandoff(handoff);

    expect(
      form.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value,
      '14:59:52',
    );
    expect(
      form.fields.any((field) => field.key == InvoiceReviewFieldKey.invoiceTime),
      isTrue,
    );
  });

  // P4.18.3 real-device regression: production Field-First reorders/decorates
  // fields, but must preserve the base transaction-time field and value.
  test('Field-First form preserves strict Local OCR transaction time', () {
    final handoff = _xy17859005Handoff();
    final form = const FieldFirstInvoiceReviewFormPresenter().fromHandoff(
      handoff,
    );

    expect(
      form.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value,
      '14:59:52',
    );
    expect(
      form.fields.any((field) => field.key == InvoiceReviewFieldKey.invoiceTime),
      isTrue,
    );
  });

  test('review and evidence contracts propagate Local time and period', () {
    final form = File(
      'lib/features/invoice/invoice_review_form_view_model.dart',
    ).readAsStringSync();
    final fieldFirst = File(
      'lib/features/invoice/invoice_field_first_review_form_presenter.dart',
    ).readAsStringSync();
    final frozen = File(
      'lib/features/invoice/invoice_frozen_review_page.dart',
    ).readAsStringSync();
    final evidence = File(
      'lib/features/invoice/invoice_recognition_evidence_exporter.dart',
    ).readAsStringSync();

    expect(form, contains('extractStrictInvoiceTime(supplementalRawText)'));
    expect(form, contains('extractCanonicalInvoicePeriod(supplementalRawText)'));
    expect(form, contains('final invoiceTime = extractStrictInvoiceTime(rawText)'));
    expect(form, contains('parsed?.randomCode?.trim()'));
    expect(
      fieldFirst,
      contains('base.fieldFor(InvoiceReviewFieldKey.invoiceTime)'),
    );
    expect(
      frozen,
      contains('local.fieldFor(InvoiceReviewFieldKey.invoicePeriod)?.value'),
    );
    expect(
      frozen,
      contains('local.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value'),
    );
    expect(
      evidence,
      contains('local.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value'),
    );
    expect(evidence, isNot(contains("('invoiceTime', '', ai.invoiceTime")));
    expect(evidence, contains('normalizeInvoicePeriodForComparison'));
  });
}

InvoiceReviewHandoffState _xy17859005Handoff() {
  final automatic = InvoiceAutomaticRecognitionResult(
    status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
    message: 'Traditional OCR candidate',
    selectedRouteReason: 'Traditional OCR',
    requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    ocrResult: TraditionalInvoiceOcrResult(
      status: TraditionalInvoiceOcrStatus.success,
      message: 'OCR ready',
      candidate: TraditionalInvoiceOcrReviewCandidate(
        sourceImageReference: '/tmp/xy17859005.jpg',
        invoiceNumber: 'XY17859005',
        sellerTaxId: '',
        sellerTaxIdSource: '',
        invoiceDate: DateTime.utc(2026, 4, 18),
        sellerName: '',
        totalAmount: null,
        visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
        confidence: const <
          TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence
        >{},
        fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
        rawText: '中華民國115年3-4月份\nXY 17859005\n2826/84/18 14:59:52',
        rawLines: const <String>[
          '中華民國115年3-4月份',
          'XY 17859005',
          '2826/84/18 14:59:52',
        ],
      ),
    ),
  );
  return const InvoiceReviewHandoffPresenter().fromAutomaticResult(automatic);
}
