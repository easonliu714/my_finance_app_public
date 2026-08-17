import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';

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

  test('review and evidence contracts propagate Local time and period', () {
    final form = File(
      'lib/features/invoice/invoice_review_form_view_model.dart',
    ).readAsStringSync();
    final frozen = File(
      'lib/features/invoice/invoice_frozen_review_page.dart',
    ).readAsStringSync();
    final evidence = File(
      'lib/features/invoice/invoice_recognition_evidence_exporter.dart',
    ).readAsStringSync();

    expect(form, contains('extractStrictInvoiceTime(supplementalRawText)'));
    expect(form, contains('extractCanonicalInvoicePeriod(supplementalRawText)'));
    expect(form, contains('parsed?.randomCode?.trim()'));
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
