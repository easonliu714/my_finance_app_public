import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:my_finance_app/features/invoice/invoice_live_adaptive_overlay.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_live_field_readiness.dart';

void main() {
  test('adaptive frame defaults wide and legacy geometry still requires two consecutive signals', () {
    var state = const InvoiceAdaptiveFrameState.initial();
    expect(state.mode, InvoiceReceiptFrameMode.wide);

    state = state.advance(InvoiceReceiptGeometrySignal.narrowTall);
    expect(state.mode, InvoiceReceiptFrameMode.wide);
    state = state.advance(InvoiceReceiptGeometrySignal.narrowTall);
    expect(state.mode, InvoiceReceiptFrameMode.narrowTall);

    state = state.advance(InvoiceReceiptGeometrySignal.wide);
    expect(state.mode, InvoiceReceiptFrameMode.narrowTall);
    state = state.advance(InvoiceReceiptGeometrySignal.wide);
    expect(state.mode, InvoiceReceiptFrameMode.wide);
  });

  test('P4.17.2 receipt intent prefers narrow after two non-electronic invoice frames', () {
    var state = const InvoiceAdaptiveFrameState.initial();
    state = state.advanceForReceiptIntent(
      invoiceNumberObserved: true,
      electronicWideEvidence: false,
    );
    expect(state.mode, InvoiceReceiptFrameMode.wide);
    state = state.advanceForReceiptIntent(
      invoiceNumberObserved: true,
      electronicWideEvidence: false,
    );
    expect(state.mode, InvoiceReceiptFrameMode.narrowTall);

    state = state.advanceForReceiptIntent(
      invoiceNumberObserved: false,
      electronicWideEvidence: false,
    );
    expect(state.mode, InvoiceReceiptFrameMode.narrowTall);

    state = state.advanceForReceiptIntent(
      invoiceNumberObserved: true,
      electronicWideEvidence: true,
    );
    expect(state.mode, InvoiceReceiptFrameMode.wide);
  });

  test('electronic wide evidence accepts invoice plus two QR locators in the wide guide', () {
    const invoice = Rect.fromLTRB(350, 360, 650, 420);
    final evidence = resolveInvoiceElectronicWideEvidence(
      lines: const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'DM90000019', imageRect: invoice),
      ],
      invoiceNumberRect: invoice,
      qrRects: const <Rect>[
        Rect.fromLTRB(260, 520, 380, 640),
        Rect.fromLTRB(620, 520, 740, 640),
      ],
      barcodeRects: const <Rect>[],
      imageSize: const Size(1000, 1000),
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.back,
      isIos: false,
    );
    expect(evidence.keepWide, isTrue);
    expect(evidence.qrCountInsideGuide, 2);
    expect(evidence.reasons, contains('invoice_plus_two_qr'));
  });

  test('electronic wide evidence accepts electronic invoice header above invoice number', () {
    const invoice = Rect.fromLTRB(350, 400, 650, 455);
    final evidence = resolveInvoiceElectronicWideEvidence(
      lines: const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(
          text: '電子發票證明聯',
          imageRect: Rect.fromLTRB(330, 300, 670, 350),
        ),
        InvoiceOcrVisualLine(text: 'DM90000019', imageRect: invoice),
      ],
      invoiceNumberRect: invoice,
      qrRects: const <Rect>[],
      barcodeRects: const <Rect>[],
      imageSize: const Size(1000, 1000),
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.back,
      isIos: false,
    );
    expect(evidence.keepWide, isTrue);
    expect(evidence.hasElectronicInvoiceHeaderAbove, isTrue);
  });

  test('electronic wide evidence accepts random code below invoice number', () {
    const invoice = Rect.fromLTRB(350, 340, 650, 395);
    final evidence = resolveInvoiceElectronicWideEvidence(
      lines: const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'DM90000019', imageRect: invoice),
        InvoiceOcrVisualLine(
          text: '隨機碼 1234',
          imageRect: Rect.fromLTRB(380, 440, 620, 490),
        ),
      ],
      invoiceNumberRect: invoice,
      qrRects: const <Rect>[],
      barcodeRects: const <Rect>[],
      imageSize: const Size(1000, 1000),
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.back,
      isIos: false,
    );
    expect(evidence.keepWide, isTrue);
    expect(evidence.hasRandomCodeBelow, isTrue);
  });

  test('electronic wide evidence accepts invoice plus 1D barcode in the wide guide', () {
    const invoice = Rect.fromLTRB(350, 360, 650, 420);
    final evidence = resolveInvoiceElectronicWideEvidence(
      lines: const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'DM90000019', imageRect: invoice),
      ],
      invoiceNumberRect: invoice,
      qrRects: const <Rect>[],
      barcodeRects: const <Rect>[
        Rect.fromLTRB(250, 520, 750, 570),
      ],
      imageSize: const Size(1000, 1000),
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.back,
      isIos: false,
    );
    expect(evidence.keepWide, isTrue);
    expect(evidence.hasOneDimensionalBarcodeInsideGuide, isTrue);
  });

  test('invoice number alone is not electronic-wide evidence', () {
    const invoice = Rect.fromLTRB(350, 360, 650, 420);
    final evidence = resolveInvoiceElectronicWideEvidence(
      lines: const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'XY90000021', imageRect: invoice),
      ],
      invoiceNumberRect: invoice,
      qrRects: const <Rect>[],
      barcodeRects: const <Rect>[],
      imageSize: const Size(1000, 1000),
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.back,
      isIos: false,
    );
    expect(evidence.keepWide, isFalse);
  });

  test('receipt geometry remains available as diagnostic telemetry', () {
    final narrow = observeInvoiceReceiptGeometry(
      imageSize: const Size(1000, 1000),
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.back,
      isIos: false,
      evidenceRects: const <Rect>[
        Rect.fromLTRB(350, 100, 650, 180),
        Rect.fromLTRB(350, 300, 650, 380),
        Rect.fromLTRB(350, 500, 650, 580),
        Rect.fromLTRB(350, 700, 650, 780),
      ],
    );
    expect(narrow.signal, InvoiceReceiptGeometrySignal.narrowTall);
    expect(narrow.heightToWidthRatio, greaterThan(1.55));

    final wide = observeInvoiceReceiptGeometry(
      imageSize: const Size(1000, 1000),
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.back,
      isIos: false,
      evidenceRects: const <Rect>[
        Rect.fromLTRB(100, 320, 900, 370),
        Rect.fromLTRB(120, 390, 880, 440),
        Rect.fromLTRB(180, 460, 820, 510),
      ],
    );
    expect(wide.signal, InvoiceReceiptGeometrySignal.wide);
  });

  test('seller tax overlay accepts explicit and NO weak labels but rejects phone formatting', () {
    const invoiceRect = Rect.fromLTRB(100, 100, 400, 160);
    const explicitRect = Rect.fromLTRB(120, 210, 390, 270);
    const noRect = Rect.fromLTRB(120, 210, 390, 270);

    final explicit = findSellerTaxVisualCandidate(
      const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'AA90000002', imageRect: invoiceRect),
        InvoiceOcrVisualLine(text: '賣方統編：38343553', imageRect: explicitRect),
      ],
      invoiceNumber: 'AA90000002',
    );
    expect(explicit?.imageRect, explicitRect);

    final weakNo = findSellerTaxVisualCandidate(
      const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'XY90000021', imageRect: invoiceRect),
        InvoiceOcrVisualLine(text: 'NO.3934D553', imageRect: noRect),
      ],
      invoiceNumber: 'XY90000021',
    );
    expect(weakNo?.imageRect, noRect);

    final phone = findSellerTaxVisualCandidate(
      const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'XY90000021', imageRect: invoiceRect),
        InvoiceOcrVisualLine(
          text: '8262-9222',
          imageRect: Rect.fromLTRB(120, 210, 390, 270),
        ),
      ],
      invoiceNumber: 'XY90000021',
    );
    expect(phone, isNull);

    final punctuatedUnlabeled = findSellerTaxVisualCandidate(
      const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'AA90000002', imageRect: invoiceRect),
        InvoiceOcrVisualLine(
          text: '2.38342557',
          imageRect: Rect.fromLTRB(120, 210, 390, 270),
        ),
      ],
      invoiceNumber: 'AA90000002',
    );
    expect(punctuatedUnlabeled, isNull);
  });

  test('unlabeled seller tax candidate must be raw pure eight digits before phone/address boundary', () {
    const invoiceRect = Rect.fromLTRB(100, 100, 400, 160);
    const taxRect = Rect.fromLTRB(120, 210, 390, 270);
    final candidate = findSellerTaxVisualCandidate(
      const <InvoiceOcrVisualLine>[
        InvoiceOcrVisualLine(text: 'XY90000021', imageRect: invoiceRect),
        InvoiceOcrVisualLine(text: '39342553', imageRect: taxRect),
        InvoiceOcrVisualLine(
          text: '電話',
          imageRect: Rect.fromLTRB(120, 290, 240, 330),
        ),
        InvoiceOcrVisualLine(
          text: '82629222',
          imageRect: Rect.fromLTRB(120, 340, 390, 390),
        ),
      ],
      invoiceNumber: 'XY90000021',
    );
    expect(candidate?.imageRect, taxRect);
  });

  test('Traditional readiness requires invoice number plus explicit eight-digit seller tax', () {
    const consensus = TraditionalLiveIdentityConsensus(
      invoiceNumber: 'XY90000021',
      invoiceObservations: 2,
      identityContextObservations: 2,
      currentFrameRelevant: true,
    );

    final missingTax = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'XY90000021',
      sellerTaxId: '',
      hasSellerIdentityContext: true,
      previousSignature: '',
      previousConsecutiveObservations: 0,
      profile: InvoiceLiveReadinessProfile.traditionalExplicitSellerTax,
    );
    expect(missingTax.identityEvidenceReady, isFalse);
    expect(missingTax.canFreeze, isFalse);

    final first = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'XY90000021',
      sellerTaxId: '39342553',
      hasSellerIdentityContext: true,
      previousSignature: '',
      previousConsecutiveObservations: 0,
      profile: InvoiceLiveReadinessProfile.traditionalExplicitSellerTax,
    );
    final second = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'XY90000021',
      sellerTaxId: '39342553',
      hasSellerIdentityContext: true,
      previousSignature: first.signature,
      previousConsecutiveObservations: first.consecutiveObservations,
      profile: InvoiceLiveReadinessProfile.traditionalExplicitSellerTax,
    );
    expect(second.stableObservations, 2);
    expect(second.canFreeze, isTrue);
  });

  test('P4.17.2 route keeps Camera/Frozen safety and adds explicit evidence gates', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();
    final adaptive = File(
      'lib/features/invoice/invoice_live_capture_adaptive_page.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/features/invoice/invoice_live_adaptive_overlay.dart',
    ).readAsStringSync();
    final readiness = File(
      'lib/features/invoice/invoice_live_field_readiness.dart',
    ).readAsStringSync();
    final stabilized = File(
      'lib/features/invoice/invoice_live_capture_stabilized_page.dart',
    ).readAsStringSync();

    expect(router, contains('AdaptiveInvoiceLiveCapturePage'));
    expect(adaptive, contains('BarcodeFormat.all'));
    expect(adaptive, contains('ELECTRONIC_WIDE_EVIDENCE'));
    expect(adaptive, contains('advanceForReceiptIntent'));
    expect(adaptive, contains('traditionalExplicitSellerTax'));
    expect(adaptive, contains('sellerTaxMatches'));
    expect(adaptive, contains('GUIDANCE_GEOMETRY_OBSERVED'));
    expect(adaptive, contains("'adaptiveGuidanceAffectsAcceptance': false"));
    expect(adaptive, contains('setFocusMode(FocusMode.locked)'));
    expect(adaptive, isNot(contains('setExposureMode(FocusMode.locked)')));
    expect(adaptive, contains('setExposureMode(ExposureMode.locked)'));
    expect(adaptive, contains('Duration(milliseconds: 250)'));
    expect(adaptive, contains('FROZEN_IDENTITY_CHECK'));
    expect(adaptive, contains('final accepted = !auto || identityMatches'));
    expect(adaptive, isNot(contains('TransactionRepository')));
    expect(adaptive, isNot(contains('TaiwanBusinessRegistryService')));

    expect(overlay, contains('InvoiceElectronicWideEvidence'));
    expect(overlay, contains('invoice_plus_two_qr'));
    expect(overlay, contains('electronic_invoice_header_above'));
    expect(overlay, contains('random_code_below'));
    expect(overlay, contains('invoice_plus_barcode'));
    expect(overlay, contains('unlabeledEightDigits'));
    expect(readiness, contains('traditionalExplicitSellerTax'));

    expect(stabilized, contains('FROZEN_IDENTITY_CHECK'));
    expect(stabilized, contains('resolveInvoiceLiveFieldReadiness'));
  });
}
