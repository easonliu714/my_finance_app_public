import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_review_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  const presenter = InvoiceReviewHandoffPresenter();

  test('QR result becomes review state with disclaimer and route reason', () {
    final state = presenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
        message: 'QR ready',
        selectedRouteReason: '找到有效電子發票 QR，優先使用 QR 覆核路徑。',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        qrResult: InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.qrCandidate,
          message: 'QR ready',
          failedImageReferences: <String>[],
        ),
      ),
    );

    expect(state.action, InvoiceReviewHandoffAction.reviewQrCandidate);
    expect(state.title, '電子發票 QR 覆核');
    expect(state.routeReason, contains('優先使用 QR'));
    expect(state.disclaimer, invoiceRecognitionDisclaimer);
    expect(state.hasDisclaimer, isTrue);
    expect(state.requiresUserReview, isTrue);
    expect(state.canCreateFormalRecord, isFalse);
    expect(state.usedNetwork, isFalse);
    expect(
      state.availableOverrides,
      contains(InvoiceReviewRouteOverride.forceTraditionalOcr),
    );
    expect(
      state.availableOverrides,
      contains(InvoiceReviewRouteOverride.forceManualQrDesignation),
    );
  });

  test('OCR result carries field warnings without allowing formal write', () {
    final state = presenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
        message: 'OCR partial',
        selectedRouteReason: '未找到有效電子發票 QR，改用本機傳統發票 OCR。',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        ocrResult: TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.partial,
          message: 'OCR partial',
          candidate: TraditionalInvoiceOcrReviewCandidate(
            sourceImageReference: '/tmp/a.jpg',
            invoiceNumber: '',
            invoiceDate: null,
            sellerName: '可見商家',
            totalAmount: null,
            visibleLineItems: <TraditionalInvoiceOcrLineItem>[],
            confidence: <TraditionalInvoiceOcrField,
                TraditionalInvoiceOcrConfidence>{},
            fieldWarnings: <TraditionalInvoiceOcrField, List<String>>{
              TraditionalInvoiceOcrField.invoiceNumber: <String>[
                '號碼模糊，請人工輸入。',
              ],
            },
          ),
        ),
      ),
    );

    expect(
      state.action,
      InvoiceReviewHandoffAction.reviewTraditionalOcrCandidate,
    );
    expect(state.warnings, contains('號碼模糊，請人工輸入。'));
    expect(state.requiresUserReview, isTrue);
    expect(state.canCreateFormalRecord, isFalse);
    expect(state.hasDisclaimer, isTrue);
  });

  test('manual QR designation keeps explicit manual action', () {
    final state = presenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.manualQrDesignation,
        message: 'Manual QR',
        selectedRouteReason: '找到 QR 證據但無法唯一配對，保留人工指定，不降級為 OCR。',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      ),
    );

    expect(state.action, InvoiceReviewHandoffAction.designateQrManually);
    expect(state.requiresManualQrDesignation, isTrue);
    expect(state.requiresUserReview, isFalse);
    expect(
      state.availableOverrides,
      contains(InvoiceReviewRouteOverride.forceTraditionalOcr),
    );
    expect(state.canCreateFormalRecord, isFalse);
  });

  test('recognition failure offers retry or manual entry only', () {
    final state = presenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.recognitionFailed,
        message: 'Failed',
        selectedRouteReason: 'QR 解碼器失敗，流程採 fail-closed。',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        qrResult: InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.decoderFailed,
          message: 'Decoder failed',
          failedImageReferences: <String>['/tmp/fail.jpg'],
        ),
      ),
    );

    expect(state.action, InvoiceReviewHandoffAction.retryCapture);
    expect(state.canRetryCapture, isTrue);
    expect(state.requiresUserReview, isFalse);
    expect(state.warnings, contains('部分影像無法本機解碼，請確認或重新拍攝。'));
    expect(
      state.availableOverrides,
      isNot(contains(InvoiceReviewRouteOverride.forceTraditionalOcr)),
    );
    expect(
      state.availableOverrides,
      contains(InvoiceReviewRouteOverride.manualEntry),
    );
  });

  test('allowed override changes route but keeps disclaimer and no-write safety', () {
    final state = presenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
        message: 'QR ready',
        selectedRouteReason: 'QR selected',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      ),
    );

    final overridden = presenter.applyOverride(
      state: state,
      override: InvoiceReviewRouteOverride.forceTraditionalOcr,
    );

    expect(
      overridden.action,
      InvoiceReviewHandoffAction.reviewTraditionalOcrCandidate,
    );
    expect(overridden.routeReason, contains('使用者改選傳統發票 OCR'));
    expect(overridden.hasDisclaimer, isTrue);
    expect(overridden.requiresUserReview, isTrue);
    expect(overridden.canCreateFormalRecord, isFalse);
  });

  test('disallowed override leaves route unchanged and adds warning', () {
    final state = presenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.recognitionFailed,
        message: 'Failed',
        selectedRouteReason: 'Failed route',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      ),
    );

    final overridden = presenter.applyOverride(
      state: state,
      override: InvoiceReviewRouteOverride.forceTraditionalOcr,
    );

    expect(overridden.action, state.action);
    expect(overridden.routeReason, state.routeReason);
    expect(overridden.warnings, contains('此覆核路徑目前不可切換。'));
    expect(overridden.canCreateFormalRecord, isFalse);
  });

  test('safe summary exposes state only, not route details', () {
    final state = presenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
        message: 'QR ready',
        selectedRouteReason: 'private route reason should not be in summary',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      ),
    );

    final safeText = state.toSafeSummary().toString();

    expect(safeText, contains('reviewQrCandidate'));
    expect(safeText, contains('hasDisclaimer: true'));
    expect(safeText, contains('canCreateFormalRecord: false'));
    expect(safeText, isNot(contains('private route reason')));
    expect(safeText, isNot(contains(invoiceRecognitionDisclaimer)));
  });
}
