import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';

void main() {
  test('portrait Live preview uses reciprocal camera aspect ratio', () {
    expect(
      invoiceLivePreviewAspectRatio(
        cameraAspectRatio: 16 / 9,
        orientation: Orientation.portrait,
      ),
      closeTo(9 / 16, 0.000001),
    );
    expect(
      invoiceLivePreviewAspectRatio(
        cameraAspectRatio: 4 / 3,
        orientation: Orientation.portrait,
      ),
      closeTo(3 / 4, 0.000001),
    );
  });

  test('landscape Live preview keeps native camera aspect ratio', () {
    expect(
      invoiceLivePreviewAspectRatio(
        cameraAspectRatio: 16 / 9,
        orientation: Orientation.landscape,
      ),
      closeTo(16 / 9, 0.000001),
    );
  });

  test('preview and guidance overlay share the same AspectRatio render box', () {
    final source = File('lib/features/invoice/invoice_live_capture_page.dart').readAsStringSync();
    final aspect = source.indexOf('aspectRatio: invoiceLivePreviewAspectRatio(');
    final preview = source.indexOf('CameraPreview(controller)', aspect);
    final overlay = source.indexOf('_ReceiptGuidanceOverlay(snapshot: _snapshot)', aspect);
    expect(aspect, greaterThanOrEqualTo(0));
    expect(preview, greaterThan(aspect));
    expect(overlay, greaterThan(preview));
    expect(source.substring(aspect, overlay), contains('child: Stack('));
  });

  test('Live seller identity accepts explicit labels or contextual checksum-valid NO header', () {
    final explicit = extractTraditionalSellerTaxIdEvidence(const <String>[
      'AA90000001',
      '一品現泡茶店',
      '統編 30340553',
    ]);
    final contextual = extractTraditionalSellerTaxIdEvidence(const <String>[
      'AA90000001',
      '一品現泡茶店',
      'NO.30340553',
    ]);
    final badOcr = extractTraditionalSellerTaxIdEvidence(const <String>[
      'AA90000001',
      '一品現泡茶店',
      'NO.30348553',
    ]);

    expect(explicit?.source, 'explicit_label');
    expect(contextual?.source, 'contextual_no_header');
    expect(contextual?.acceptedForLive, isTrue);
    expect(badOcr, isNull);
  });

  test('traditional OCR carries raw evidence without leaking it to safe summary', () {
    final model = File('lib/features/invoice/traditional_invoice_ocr_review.dart').readAsStringSync();
    final parser = File('lib/features/invoice/google_mlkit_traditional_invoice_recognizer.dart').readAsStringSync();

    expect(model, contains('final String rawText;'));
    expect(model, contains('final List<String> rawLines;'));
    expect(model, contains('final String? sellerTaxId;'));
    expect(parser, contains('extractTraditionalSellerTaxIdEvidence'));
    expect(parser, contains('rawText: document.fullText'));
    expect(parser, contains('rawLines: List<String>.unmodifiable(document.lines)'));
    expect(
      model.substring(
        model.indexOf('Map<String, Object?> toSafeSummary()'),
        model.indexOf('class TraditionalInvoiceOcrResult'),
      ),
      isNot(contains("'rawText'")),
    );
  });
}
