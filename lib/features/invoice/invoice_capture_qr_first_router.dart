import 'image_capture_staging.dart';
import 'invoice_import_staging.dart';
import 'invoice_qr_parser.dart';

enum InvoiceCaptureQrRouteStatus {
  localQrCandidate,
  noQrFound,
  localQrInvalid,
  decoderFailed,
}

class InvoiceCaptureQrRouteResult {
  const InvoiceCaptureQrRouteResult({
    required this.status,
    required this.message,
    this.parseResult,
    this.stagingCandidate,
  });

  final InvoiceCaptureQrRouteStatus status;
  final String message;
  final InvoiceQrParseResult? parseResult;
  final InvoiceImportStagingItem? stagingCandidate;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get hasReviewCandidate => stagingCandidate != null;
  bool get mayOfferExternalFallback =>
      status != InvoiceCaptureQrRouteStatus.localQrCandidate;
}

class LocalInvoiceQrDecoderDiagnostics {
  const LocalInvoiceQrDecoderDiagnostics({
    required this.imageReference,
    required this.detectedCodeCount,
    required this.acceptedPayloadCount,
    required this.emptyPayloadCount,
    required this.duplicatePayloadCount,
    required this.ignoredNonQrCodeCount,
    this.failureCode,
  });

  final String imageReference;
  final int detectedCodeCount;
  final int acceptedPayloadCount;
  final int emptyPayloadCount;
  final int duplicatePayloadCount;
  final int ignoredNonQrCodeCount;
  final String? failureCode;

  bool get failed => failureCode != null;
  bool get exposesRawPayload => false;

  Map<String, Object?> toSafeMap() {
    return <String, Object?>{
      'imageReference': imageReference,
      'detectedCodeCount': detectedCodeCount,
      'acceptedPayloadCount': acceptedPayloadCount,
      'emptyPayloadCount': emptyPayloadCount,
      'duplicatePayloadCount': duplicatePayloadCount,
      'ignoredNonQrCodeCount': ignoredNonQrCodeCount,
      'failureCode': failureCode,
    };
  }
}

abstract class LocalInvoiceQrDecoder {
  Future<List<String>> decodeLocalImage(String localReference);
}

abstract class LocalInvoiceQrDecoderDiagnosticsProvider {
  LocalInvoiceQrDecoderDiagnostics? diagnosticsFor(String localReference);
}

class InvoiceCaptureQrFirstRouter {
  const InvoiceCaptureQrFirstRouter({
    required this.decoder,
    this.parser = const InvoiceQrParser(),
    this.clock,
    this.idFactory,
  });

  final LocalInvoiceQrDecoder decoder;
  final InvoiceQrParser parser;
  final DateTime Function()? clock;
  final String Function()? idFactory;

  Future<InvoiceCaptureQrRouteResult> route(
    ImageCaptureStagingItem image,
  ) async {
    if (!image.needsReview || image.localReference.trim().isEmpty) {
      return const InvoiceCaptureQrRouteResult(
        status: InvoiceCaptureQrRouteStatus.decoderFailed,
        message: '本機影像狀態不可辨識，請重新選擇影像。',
      );
    }

    try {
      final payloads = await decoder.decodeLocalImage(
        image.localReference.trim(),
      );
      final normalized = payloads
          .map((payload) => payload.trim())
          .where((payload) => payload.isNotEmpty)
          .toList(growable: false);
      if (normalized.isEmpty) {
        return const InvoiceCaptureQrRouteResult(
          status: InvoiceCaptureQrRouteStatus.noQrFound,
          message: '本機未找到可解析的發票 QR；可改用手動輸入或另行同意外部辨識。',
        );
      }

      InvoiceQrParseResult? firstInvalid;
      for (final payload in normalized) {
        final result = parser.parse(payload);
        if (!result.canStageCandidate) {
          firstInvalid ??= result;
          continue;
        }
        final createdAt = clock?.call() ?? DateTime.now().toUtc();
        final candidate = result.toStagingItemCandidate(
          id: idFactory?.call() ??
              'capture-qr-${createdAt.microsecondsSinceEpoch}',
          note: '來源影像：${image.fileName}',
          now: createdAt,
        );
        return InvoiceCaptureQrRouteResult(
          status: InvoiceCaptureQrRouteStatus.localQrCandidate,
          parseResult: result,
          stagingCandidate: candidate,
          message: '已用本機 QR 解析建立待審核發票候選；尚未建立正式發票或交易。',
        );
      }

      return InvoiceCaptureQrRouteResult(
        status: InvoiceCaptureQrRouteStatus.localQrInvalid,
        parseResult: firstInvalid,
        message: firstInvalid == null
            ? '本機 QR 資料不可解析，請人工確認。'
            : '本機 QR 資料不可解析：${firstInvalid.errorSummary}',
      );
    } catch (_) {
      return const InvoiceCaptureQrRouteResult(
        status: InvoiceCaptureQrRouteStatus.decoderFailed,
        message: '本機 QR 辨識失敗，影像仍保留在待審核狀態。',
      );
    }
  }
}
