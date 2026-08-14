import 'image_capture_staging.dart';
import 'invoice_capture_qr_first_router.dart';
import 'invoice_recognition_router.dart';

enum InvoiceLocalRecognitionRequestMode {
  automatic,
  qrOnly,
}

enum InvoiceLocalRecognitionStatus {
  qrCandidate,
  ocrFallback,
  manualQrDesignation,
  decoderFailed,
  invalidInput,
}

class InvoiceLocalRecognitionResult {
  const InvoiceLocalRecognitionResult({
    required this.status,
    required this.message,
    required this.failedImageReferences,
    this.routingResult,
    this.decoderDiagnostics = const <LocalInvoiceQrDecoderDiagnostics>[],
  });

  final InvoiceLocalRecognitionStatus status;
  final String message;
  final List<String> failedImageReferences;
  final InvoiceRecognitionRoutingResult? routingResult;
  final List<LocalInvoiceQrDecoderDiagnostics> decoderDiagnostics;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get hasReviewCandidate => routingResult?.hasReviewCandidate == true;
  bool get requiresManualQrDesignation =>
      status == InvoiceLocalRecognitionStatus.manualQrDesignation;
}

class InvoiceLocalRecognitionCoordinator {
  const InvoiceLocalRecognitionCoordinator({
    required this.decoder,
    this.router = const InvoiceRecognitionRouter(),
  });

  final LocalInvoiceQrDecoder decoder;
  final InvoiceRecognitionRouter router;

  Future<InvoiceLocalRecognitionResult> recognize({
    required List<ImageCaptureStagingItem> images,
    InvoiceLocalRecognitionRequestMode mode =
        InvoiceLocalRecognitionRequestMode.automatic,
  }) async {
    final validImages = images
        .where(
          (image) =>
              image.needsReview && image.localReference.trim().isNotEmpty,
        )
        .toList(growable: false);

    if (validImages.isEmpty) {
      return const InvoiceLocalRecognitionResult(
        status: InvoiceLocalRecognitionStatus.invalidInput,
        message: '沒有可供本機辨識的待審核影像。',
        failedImageReferences: <String>[],
      );
    }

    final decodedInputs = <InvoiceRecognitionImageInput>[];
    final failedReferences = <String>[];
    final decoderDiagnostics = <LocalInvoiceQrDecoderDiagnostics>[];
    final diagnosticsProvider =
        decoder is LocalInvoiceQrDecoderDiagnosticsProvider
            ? decoder as LocalInvoiceQrDecoderDiagnosticsProvider
            : null;

    for (final image in validImages) {
      final reference = image.localReference.trim();
      try {
        final payloads = await decoder.decodeLocalImage(reference);
        decodedInputs.add(
          InvoiceRecognitionImageInput(
            localReference: reference,
            fileName: image.fileName,
            payloads: List<String>.unmodifiable(payloads),
          ),
        );
      } catch (_) {
        failedReferences.add(reference);
      } finally {
        final diagnostics = diagnosticsProvider?.diagnosticsFor(reference);
        if (diagnostics != null) {
          decoderDiagnostics.add(diagnostics);
        }
      }
    }

    if (decodedInputs.isEmpty) {
      return InvoiceLocalRecognitionResult(
        status: InvoiceLocalRecognitionStatus.decoderFailed,
        message: '本機 QR 解碼失敗；影像仍保留在待審核狀態。',
        failedImageReferences: List<String>.unmodifiable(failedReferences),
        decoderDiagnostics:
            List<LocalInvoiceQrDecoderDiagnostics>.unmodifiable(
          decoderDiagnostics,
        ),
      );
    }

    final routingResult = router.route(decodedInputs);

    if (mode == InvoiceLocalRecognitionRequestMode.qrOnly &&
        routingResult.route == InvoiceRecognitionRoute.traditionalOcr) {
      return InvoiceLocalRecognitionResult(
        status: InvoiceLocalRecognitionStatus.manualQrDesignation,
        message: '未找到有效電子發票 QR，請重新拍攝或手動指定左碼與右碼。',
        routingResult: routingResult,
        failedImageReferences: List<String>.unmodifiable(failedReferences),
        decoderDiagnostics:
            List<LocalInvoiceQrDecoderDiagnostics>.unmodifiable(
          decoderDiagnostics,
        ),
      );
    }

    final status = switch (routingResult.route) {
      InvoiceRecognitionRoute.electronicInvoiceQr =>
        InvoiceLocalRecognitionStatus.qrCandidate,
      InvoiceRecognitionRoute.traditionalOcr =>
        InvoiceLocalRecognitionStatus.ocrFallback,
      InvoiceRecognitionRoute.manualQrDesignation =>
        InvoiceLocalRecognitionStatus.manualQrDesignation,
    };

    return InvoiceLocalRecognitionResult(
      status: status,
      message: _messageFor(
        routingResult: routingResult,
        failedImageCount: failedReferences.length,
      ),
      routingResult: routingResult,
      failedImageReferences: List<String>.unmodifiable(failedReferences),
      decoderDiagnostics: List<LocalInvoiceQrDecoderDiagnostics>.unmodifiable(
        decoderDiagnostics,
      ),
    );
  }

  static String _messageFor({
    required InvoiceRecognitionRoutingResult routingResult,
    required int failedImageCount,
  }) {
    if (failedImageCount == 0) return routingResult.message;
    return '${routingResult.message}；另有 $failedImageCount 張影像解碼失敗。';
  }
}
