import 'image_capture_staging.dart';
import 'invoice_local_recognition_coordinator.dart';
import 'traditional_invoice_ocr_review.dart';

enum InvoiceAutomaticRecognitionStatus {
  qrReviewCandidate,
  ocrReviewCandidate,
  manualQrDesignation,
  recognitionFailed,
  invalidInput,
}

enum InvoiceRecognitionRequestedRoute {
  automatic,
  electronicInvoiceQr,
  traditionalInvoiceOcr,
}

typedef InvoiceQrRecognitionRunner =
    Future<InvoiceLocalRecognitionResult> Function({
      required List<ImageCaptureStagingItem> images,
      required InvoiceLocalRecognitionRequestMode mode,
    });

typedef TraditionalInvoiceOcrRunner =
    Future<TraditionalInvoiceOcrResult> Function(String localReference);

class InvoiceAutomaticRecognitionResult {
  const InvoiceAutomaticRecognitionResult({
    required this.status,
    required this.message,
    required this.selectedRouteReason,
    required this.requestedRoute,
    this.qrResult,
    this.ocrResult,
  });

  final InvoiceAutomaticRecognitionStatus status;
  final String message;
  final String selectedRouteReason;
  final InvoiceRecognitionRequestedRoute requestedRoute;
  final InvoiceLocalRecognitionResult? qrResult;
  final TraditionalInvoiceOcrResult? ocrResult;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get hasReviewCandidate =>
      qrResult?.hasReviewCandidate == true ||
      ocrResult?.hasReviewCandidate == true;
  bool get requiresManualQrDesignation =>
      status == InvoiceAutomaticRecognitionStatus.manualQrDesignation;
  bool get wasUserOverridden =>
      requestedRoute != InvoiceRecognitionRequestedRoute.automatic;
}

class InvoiceAutomaticRecognitionCoordinator {
  const InvoiceAutomaticRecognitionCoordinator({
    required this.qrRunner,
    required this.ocrRunner,
  });

  factory InvoiceAutomaticRecognitionCoordinator.fromCoordinators({
    required InvoiceLocalRecognitionCoordinator qrCoordinator,
    required TraditionalInvoiceOcrCoordinator ocrCoordinator,
  }) {
    return InvoiceAutomaticRecognitionCoordinator(
      qrRunner: qrCoordinator.recognize,
      ocrRunner: ocrCoordinator.recognize,
    );
  }

  final InvoiceQrRecognitionRunner qrRunner;
  final TraditionalInvoiceOcrRunner ocrRunner;

  Future<InvoiceAutomaticRecognitionResult> recognize({
    required List<ImageCaptureStagingItem> images,
    InvoiceRecognitionRequestedRoute requestedRoute =
        InvoiceRecognitionRequestedRoute.automatic,
  }) async {
    final validImages = images
        .where((image) => image.canRunLocalRecognition)
        .toList(growable: false);

    if (validImages.isEmpty) {
      return InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.invalidInput,
        message: '沒有可供本機辨識的待審核影像。',
        selectedRouteReason: '輸入影像無效、已放棄或已清除暫存參照，未執行 QR 或 OCR。',
        requestedRoute: requestedRoute,
      );
    }

    switch (requestedRoute) {
      case InvoiceRecognitionRequestedRoute.automatic:
        return _runAutomatic(validImages);
      case InvoiceRecognitionRequestedRoute.electronicInvoiceQr:
        return _runQrOnly(validImages);
      case InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr:
        return _runOcr(
          image: validImages.first,
          requestedRoute: requestedRoute,
          selectedRouteReason: '使用者改用本機傳統發票 OCR 覆核路徑。',
        );
    }
  }

  Future<InvoiceAutomaticRecognitionResult> _runAutomatic(
    List<ImageCaptureStagingItem> validImages,
  ) async {
    final qrResult = await qrRunner(
      images: validImages,
      mode: InvoiceLocalRecognitionRequestMode.automatic,
    );

    switch (qrResult.status) {
      case InvoiceLocalRecognitionStatus.qrCandidate:
        return _runQrWithSupplementalOcr(
          validImages: validImages,
          qrResult: qrResult,
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
          selectedRouteReason:
              '找到有效電子發票 QR，QR 維持 identity authority；另執行一次本機 OCR 補充時間與商家欄位。',
        );
      case InvoiceLocalRecognitionStatus.manualQrDesignation:
        return InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.manualQrDesignation,
          message: qrResult.message,
          selectedRouteReason: '找到 QR 證據但無法唯一配對，保留人工指定，不降級為 OCR。',
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
          qrResult: qrResult,
        );
      case InvoiceLocalRecognitionStatus.ocrFallback:
        return _runOcr(
          image: validImages.first,
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
          selectedRouteReason: '未找到有效電子發票 QR，改用本機傳統發票 OCR。',
          qrResult: qrResult,
        );
      case InvoiceLocalRecognitionStatus.decoderFailed:
        return InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.recognitionFailed,
          message: '本機 QR 解碼失敗，為避免誤判未自動改走 OCR。',
          selectedRouteReason: 'QR 解碼器失敗，流程採 fail-closed。',
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
          qrResult: qrResult,
        );
      case InvoiceLocalRecognitionStatus.invalidInput:
        return InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.invalidInput,
          message: qrResult.message,
          selectedRouteReason: 'QR 前置檢查判定輸入無效，未執行 OCR。',
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
          qrResult: qrResult,
        );
    }
  }

  Future<InvoiceAutomaticRecognitionResult> _runQrOnly(
    List<ImageCaptureStagingItem> validImages,
  ) async {
    final qrResult = await qrRunner(
      images: validImages,
      mode: InvoiceLocalRecognitionRequestMode.qrOnly,
    );

    switch (qrResult.status) {
      case InvoiceLocalRecognitionStatus.qrCandidate:
        return _runQrWithSupplementalOcr(
          validImages: validImages,
          qrResult: qrResult,
          requestedRoute: InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
          selectedRouteReason:
              '使用者指定電子發票 QR；QR 維持 identity authority，另執行一次本機 OCR 補充時間與商家欄位。',
        );
      case InvoiceLocalRecognitionStatus.manualQrDesignation:
      case InvoiceLocalRecognitionStatus.ocrFallback:
        return InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.manualQrDesignation,
          message: qrResult.message,
          selectedRouteReason: '使用者指定 QR 路徑，但仍需人工指定或補拍 QR。',
          requestedRoute: InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
          qrResult: qrResult,
        );
      case InvoiceLocalRecognitionStatus.decoderFailed:
        return InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.recognitionFailed,
          message: qrResult.message,
          selectedRouteReason: '使用者指定 QR 路徑，但本機 QR 解碼失敗。',
          requestedRoute: InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
          qrResult: qrResult,
        );
      case InvoiceLocalRecognitionStatus.invalidInput:
        return InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.invalidInput,
          message: qrResult.message,
          selectedRouteReason: '使用者指定 QR 路徑，但輸入影像無效。',
          requestedRoute: InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
          qrResult: qrResult,
        );
    }
  }

  Future<InvoiceAutomaticRecognitionResult> _runQrWithSupplementalOcr({
    required List<ImageCaptureStagingItem> validImages,
    required InvoiceLocalRecognitionResult qrResult,
    required InvoiceRecognitionRequestedRoute requestedRoute,
    required String selectedRouteReason,
  }) async {
    TraditionalInvoiceOcrResult? supplemental;
    try {
      supplemental = await ocrRunner(validImages.first.localReference.trim());
    } catch (_) {
      supplemental = null;
    }
    return InvoiceAutomaticRecognitionResult(
      status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
      message: supplemental == null
          ? '${qrResult.message}；本機 OCR 補充失敗，QR 候選仍保留。'
          : '${qrResult.message}；已完成本機 OCR 補充讀取。',
      selectedRouteReason: selectedRouteReason,
      requestedRoute: requestedRoute,
      qrResult: qrResult,
      ocrResult: supplemental,
    );
  }

  Future<InvoiceAutomaticRecognitionResult> _runOcr({
    required ImageCaptureStagingItem image,
    required InvoiceRecognitionRequestedRoute requestedRoute,
    required String selectedRouteReason,
    InvoiceLocalRecognitionResult? qrResult,
  }) async {
    final ocrResult = await ocrRunner(image.localReference.trim());
    if (ocrResult.hasReviewCandidate) {
      return InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
        message: ocrResult.message,
        selectedRouteReason: selectedRouteReason,
        requestedRoute: requestedRoute,
        qrResult: qrResult,
        ocrResult: ocrResult,
      );
    }

    return InvoiceAutomaticRecognitionResult(
      status: ocrResult.status == TraditionalInvoiceOcrStatus.invalidInput
          ? InvoiceAutomaticRecognitionStatus.invalidInput
          : InvoiceAutomaticRecognitionStatus.recognitionFailed,
      message: ocrResult.message,
      selectedRouteReason:
          requestedRoute == InvoiceRecognitionRequestedRoute.automatic
          ? '未找到有效 QR，且本機 OCR 未建立覆核候選。'
          : '使用者指定 OCR 路徑，但本機 OCR 未建立覆核候選。',
      requestedRoute: requestedRoute,
      qrResult: qrResult,
      ocrResult: ocrResult,
    );
  }
}
