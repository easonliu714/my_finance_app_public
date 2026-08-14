import 'package:mobile_scanner/mobile_scanner.dart';

import 'invoice_capture_qr_first_router.dart';

enum InvoiceQrDecodedFormat {
  qrCode,
  other,
}

class InvoiceQrDecodedBarcode {
  const InvoiceQrDecodedBarcode({
    required this.format,
    this.rawValue,
  });

  final InvoiceQrDecodedFormat format;
  final String? rawValue;
}

class InvoiceQrImageAnalysis {
  const InvoiceQrImageAnalysis({
    required this.barcodes,
  });

  final List<InvoiceQrDecodedBarcode> barcodes;
}

abstract class InvoiceQrImageAnalyzer {
  Future<InvoiceQrImageAnalysis> analyze(String localReference);
}

typedef MobileScannerControllerFactory = MobileScannerController Function();

class MobileScannerQrImageAnalyzer implements InvoiceQrImageAnalyzer {
  MobileScannerQrImageAnalyzer({
    MobileScannerControllerFactory? controllerFactory,
  }) : _controllerFactory = controllerFactory ?? _createController;

  final MobileScannerControllerFactory _controllerFactory;

  static MobileScannerController _createController() {
    return MobileScannerController(
      autoStart: false,
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    );
  }

  @override
  Future<InvoiceQrImageAnalysis> analyze(String localReference) async {
    final controller = _controllerFactory();
    try {
      final capture = await controller.analyzeImage(localReference);
      final barcodes = capture?.barcodes ?? const <Barcode>[];
      return InvoiceQrImageAnalysis(
        barcodes: List<InvoiceQrDecodedBarcode>.unmodifiable(
          barcodes.map(
            (barcode) => InvoiceQrDecodedBarcode(
              format: barcode.format == BarcodeFormat.qrCode
                  ? InvoiceQrDecodedFormat.qrCode
                  : InvoiceQrDecodedFormat.other,
              rawValue: barcode.rawValue,
            ),
          ),
        ),
      );
    } finally {
      await controller.dispose();
    }
  }
}

class NativeInvoiceQrDecoder
    implements
        LocalInvoiceQrDecoder,
        LocalInvoiceQrDecoderDiagnosticsProvider {
  NativeInvoiceQrDecoder({
    InvoiceQrImageAnalyzer? analyzer,
  }) : analyzer = analyzer ?? MobileScannerQrImageAnalyzer();

  final InvoiceQrImageAnalyzer analyzer;
  final Map<String, LocalInvoiceQrDecoderDiagnostics>
      _diagnosticsByReference =
      <String, LocalInvoiceQrDecoderDiagnostics>{};

  @override
  Future<List<String>> decodeLocalImage(String localReference) async {
    final reference = localReference.trim();
    if (reference.isEmpty) {
      _diagnosticsByReference[reference] =
          const LocalInvoiceQrDecoderDiagnostics(
        imageReference: '',
        detectedCodeCount: 0,
        acceptedPayloadCount: 0,
        emptyPayloadCount: 0,
        duplicatePayloadCount: 0,
        ignoredNonQrCodeCount: 0,
        failureCode: 'empty_image_reference',
      );
      throw ArgumentError.value(localReference, 'localReference');
    }

    try {
      final analysis = await analyzer.analyze(reference);
      final payloads = <String>[];
      final seenPayloads = <String>{};
      var emptyPayloadCount = 0;
      var duplicatePayloadCount = 0;
      var ignoredNonQrCodeCount = 0;

      for (final barcode in analysis.barcodes) {
        if (barcode.format != InvoiceQrDecodedFormat.qrCode) {
          ignoredNonQrCodeCount += 1;
          continue;
        }

        final payload = barcode.rawValue?.trim() ?? '';
        if (payload.isEmpty) {
          emptyPayloadCount += 1;
          continue;
        }
        if (!seenPayloads.add(payload)) {
          duplicatePayloadCount += 1;
          continue;
        }
        payloads.add(payload);
      }

      _diagnosticsByReference[reference] = LocalInvoiceQrDecoderDiagnostics(
        imageReference: reference,
        detectedCodeCount: analysis.barcodes.length,
        acceptedPayloadCount: payloads.length,
        emptyPayloadCount: emptyPayloadCount,
        duplicatePayloadCount: duplicatePayloadCount,
        ignoredNonQrCodeCount: ignoredNonQrCodeCount,
      );

      return List<String>.unmodifiable(payloads);
    } catch (error) {
      _diagnosticsByReference[reference] =
          LocalInvoiceQrDecoderDiagnostics(
        imageReference: reference,
        detectedCodeCount: 0,
        acceptedPayloadCount: 0,
        emptyPayloadCount: 0,
        duplicatePayloadCount: 0,
        ignoredNonQrCodeCount: 0,
        failureCode: error.runtimeType.toString(),
      );
      rethrow;
    }
  }

  @override
  LocalInvoiceQrDecoderDiagnostics? diagnosticsFor(String localReference) {
    return _diagnosticsByReference[localReference.trim()];
  }
}
