import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P4.15.2 production wiring remains local and review only', () {
    final capturePage = File(
      'lib/features/invoice/invoice_capture_page.dart',
    ).readAsStringSync();
    final reviewFlow = File(
      'lib/features/invoice/invoice_capture_review_flow.dart',
    ).readAsStringSync();
    final reviewContract = File(
      'lib/features/invoice/invoice_review_handoff_contract.dart',
    ).readAsStringSync();
    final staging = File(
      'lib/features/invoice/production_image_capture.dart',
    ).readAsStringSync();
    final qrDecoder = File(
      'lib/features/invoice/mobile_scanner_invoice_qr_decoder.dart',
    ).readAsStringSync();
    final qrDiagnostics = File(
      'lib/features/invoice/invoice_capture_qr_first_router.dart',
    ).readAsStringSync();
    final ocrAdapter = File(
      'lib/features/invoice/google_mlkit_traditional_invoice_recognizer.dart',
    ).readAsStringSync();
    final appPubspec = File('pubspec.yaml').readAsStringSync();
    final modelGradle = File(
      'packages/local_chinese_text_model/android/build.gradle',
    ).readAsStringSync();

    expect(capturePage, contains('NativeInvoiceQrDecoder()'));
    expect(
      capturePage,
      contains('GoogleMlKitTraditionalInvoiceRecognizer()'),
    );
    expect(capturePage, contains('InvoiceReviewFormCard'));
    expect(capturePage, isNot(contains('OCR 尚未啟用')));

    expect(
      reviewContract,
      contains('發票紀錄僅供記帳與對獎，不能作為兌獎憑證。'),
    );
    expect(reviewContract, contains('disclaimer: invoiceRecognitionDisclaimer'));
    expect(reviewContract, contains('bool get canCreateFormalRecord => false;'));
    expect(reviewContract, contains('bool get usedNetwork => false;'));

    expect(reviewFlow, contains('bool get canCreateFormalRecord => false;'));
    expect(reviewFlow, contains('bool get usedNetwork => false;'));

    expect(staging, contains('replayRejected'));
    expect(staging, contains('markCurrentConsumed'));
    expect(staging, contains('attachRecognitionPayloads'));
    expect(staging, contains('discardCurrent'));

    expect(qrDecoder, contains('analyzeImage'));
    expect(qrDiagnostics, contains('bool get exposesRawPayload => false;'));
    expect(
      ocrAdapter,
      contains('TextRecognitionScript.chinese'),
    );

    expect(appPubspec, contains('mobile_scanner: ^7.2.0'));
    expect(
      appPubspec,
      contains('google_mlkit_text_recognition: ^0.15.1'),
    );
    expect(appPubspec, contains('local_chinese_text_model:'));
    expect(
      modelGradle,
      contains('com.google.mlkit:text-recognition-chinese:16.0.1'),
    );
  });

  test('P4.15.2 required scenario tests remain present', () {
    final nativeQrTests = File(
      'test/p4_15_2_native_qr_decoder_test.dart',
    ).readAsStringSync();
    final routerTests = File(
      'test/p4_15_2_invoice_recognition_router_test.dart',
    ).readAsStringSync();
    final ocrTests = File(
      'test/p4_15_2_traditional_invoice_text_parser_test.dart',
    ).readAsStringSync();
    final reviewTests = File(
      'test/p4_15_2_invoice_review_form_safety_test.dart',
    ).readAsStringSync();
    final stagingTests = File(
      'test/p4_15_0_production_image_capture_test.dart',
    ).readAsStringSync();

    expect(nativeQrTests, contains('one image with left and right QR'));
    expect(nativeQrTests, contains('separate images are decoded and paired'));
    expect(nativeQrTests, contains('no detected QR remains a local OCR fallback'));
    expect(nativeQrTests, contains('native analyzer failure'));

    expect(routerTests, contains('manual designation creates a complete'));
    expect(routerTests, contains('left-only review candidate'));
    expect(routerTests, contains('right-only evidence cannot'));
    expect(routerTests, contains('out-of-range manual selection'));

    expect(ocrTests, contains('TraditionalInvoiceOcrStatus.success'));
    expect(ocrTests, contains('TraditionalInvoiceOcrStatus.partial'));
    expect(ocrTests, contains('canCreateFormalRecord, isFalse'));
    expect(ocrTests, contains('usedNetwork, isFalse'));

    expect(reviewTests, contains('disclaimer acknowledgement'));
    expect(reviewTests, contains('canSubmitReviewSafely'));
    expect(reviewTests, contains('canCreateFormalRecord, isFalse'));
    expect(reviewTests, contains('blocked result has no editable review form'));

    expect(stagingTests, contains('replayRejected'));
    expect(stagingTests, contains('currentRecognitionPayloads'));
    expect(stagingTests, contains('discard removes local reference'));
  });
}
