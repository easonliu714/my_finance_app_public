import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/invoice_live_adaptive_overlay.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_capture_policy.dart';

void main() {
  test('3-of-7 non-consecutive structural evidence authorizes capture only', () {
    var window = <bool>[];
    InvoiceSellerTaxCaptureOnlyDecision decision =
        resolveInvoiceSellerTaxCaptureOnly(
      previousWindow: window,
      currentStructuralEvidence: true,
      invoiceGreen: true,
      electronicWideEvidence: false,
    );
    window = decision.window;
    expect(decision.evidenceCount, 1);
    expect(decision.ready, isFalse);

    for (final value in <bool>[false, true, false, true]) {
      decision = resolveInvoiceSellerTaxCaptureOnly(
        previousWindow: window,
        currentStructuralEvidence: value,
        invoiceGreen: true,
        electronicWideEvidence: false,
      );
      window = decision.window;
    }
    expect(decision.evidenceCount, 3);
    expect(decision.ready, isTrue);
  });

  test('structural evidence cannot freeze before invoice green', () {
    final decision = resolveInvoiceSellerTaxCaptureOnly(
      previousWindow: const <bool>[true, true],
      currentStructuralEvidence: true,
      invoiceGreen: false,
      electronicWideEvidence: false,
    );
    expect(decision.evidenceCount, 3);
    expect(decision.ready, isFalse);
  });

  test('electronic wide evidence disables Traditional capture-only path', () {
    final decision = resolveInvoiceSellerTaxCaptureOnly(
      previousWindow: const <bool>[true, true],
      currentStructuralEvidence: true,
      invoiceGreen: true,
      electronicWideEvidence: true,
    );
    expect(decision.ready, isFalse);
  });

  test('rolling window evicts evidence older than seven samples', () {
    var window = const <bool>[true, true, true, false, false, false, false];
    final decision = resolveInvoiceSellerTaxCaptureOnly(
      previousWindow: window,
      currentStructuralEvidence: false,
      invoiceGreen: true,
      electronicWideEvidence: false,
    );
    expect(decision.window.length, 7);
    expect(decision.evidenceCount, 2);
    expect(decision.ready, isFalse);
  });

  test('checksum-invalid eight digits below invoice are structural only', () {
    final lines = <InvoiceOcrVisualLine>[
      const InvoiceOcrVisualLine(
        text: 'ZZ00000001',
        imageRect: Rect.fromLTRB(100, 100, 300, 120),
      ),
      const InvoiceOcrVisualLine(
        text: '00000059',
        imageRect: Rect.fromLTRB(120, 150, 260, 170),
      ),
    ];
    final structural = findSellerTaxStructuralEvidence(
      lines,
      invoiceNumber: 'ZZ00000001',
    );
    expect(structural?.source, 'positional_8digit_structure');

    final authoritative = extractTraditionalSellerTaxIdEvidence(
      const <String>['ZZ00000001', '測試商店', 'N0.00000059'],
    );
    expect(authoritative, isNull);
  });

  test('weak-label 7-9 glyph rows may be structural without value repair', () {
    for (final token in <String>['0B00058', '00B00058', '000B00058']) {
      final structural = findSellerTaxStructuralEvidence(
        <InvoiceOcrVisualLine>[
const InvoiceOcrVisualLine(
  text: 'ZZ00000001',
  imageRect: Rect.fromLTRB(100, 100, 300, 120),
),
InvoiceOcrVisualLine(
  text: 'H0.$token',
  imageRect: const Rect.fromLTRB(120, 150, 280, 170),
),
        ],
        invoiceNumber: 'ZZ00000001',
      );
      expect(structural, isNotNull, reason: token);
      expect(structural?.source, 'weak_label_structure', reason: token);
    }
  });

  test('far-away or phone-like number is not structural seller-tax evidence', () {
    final farAway = findSellerTaxStructuralEvidence(
      const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(
text: 'ZZ00000001',
imageRect: Rect.fromLTRB(100, 100, 300, 120),
        ),
        InvoiceOcrVisualLine(
text: '00000059',
imageRect: Rect.fromLTRB(120, 500, 260, 520),
        ),
      ],
      invoiceNumber: 'ZZ00000001',
    );
    final phone = findSellerTaxStructuralEvidence(
      const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(
text: 'ZZ00000001',
imageRect: Rect.fromLTRB(100, 100, 300, 120),
        ),
        InvoiceOcrVisualLine(
text: 'TEL.00000059',
imageRect: Rect.fromLTRB(120, 150, 280, 170),
        ),
      ],
      invoiceNumber: 'ZZ00000001',
    );
    expect(farAway, isNull);
    expect(phone, isNull);
  });

  test('adaptive page keeps Yellow value non-authoritative after capture', () {
    final adaptive = File(
      'lib/features/invoice/invoice_live_capture_adaptive_page.dart',
    ).readAsStringSync();
    expect(adaptive, contains('captureOnly ||'));
    expect(adaptive, contains("'authoritativeSellerTaxPromoted': false"));
    expect(
      adaptive,
      contains("'captureOnlySellerTaxMayRemainUnresolved': captureOnly"),
    );
    expect(adaptive, contains('frozenSellerTaxRecovered'));
  });
}
