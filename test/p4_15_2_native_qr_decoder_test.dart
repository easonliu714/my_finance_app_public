import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/mobile_scanner_invoice_qr_decoder.dart';

void main() {
  const leftPayload =
      'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';
  const rightPayload = '**detail-payload';

  test('native decoder keeps unique QR payloads and safe diagnostics', () async {
    final decoder = NativeInvoiceQrDecoder(
      analyzer: const _FakeAnalyzer(
        <String, InvoiceQrImageAnalysis>{
          '/tmp/invoice.jpg': InvoiceQrImageAnalysis(
            barcodes: <InvoiceQrDecodedBarcode>[
              InvoiceQrDecodedBarcode(
                format: InvoiceQrDecodedFormat.qrCode,
                rawValue: leftPayload,
              ),
              InvoiceQrDecodedBarcode(
                format: InvoiceQrDecodedFormat.qrCode,
                rawValue: rightPayload,
              ),
              InvoiceQrDecodedBarcode(
                format: InvoiceQrDecodedFormat.qrCode,
                rawValue: leftPayload,
              ),
              InvoiceQrDecodedBarcode(
                format: InvoiceQrDecodedFormat.qrCode,
                rawValue: '   ',
              ),
              InvoiceQrDecodedBarcode(
                format: InvoiceQrDecodedFormat.other,
                rawValue: 'private-non-qr-value',
              ),
            ],
          ),
        },
      ),
    );

    final payloads = await decoder.decodeLocalImage('/tmp/invoice.jpg');
    final diagnostics = decoder.diagnosticsFor('/tmp/invoice.jpg');

    expect(payloads, <String>[leftPayload, rightPayload]);
    expect(diagnostics, isNotNull);
    expect(diagnostics?.detectedCodeCount, 5);
    expect(diagnostics?.acceptedPayloadCount, 2);
    expect(diagnostics?.duplicatePayloadCount, 1);
    expect(diagnostics?.emptyPayloadCount, 1);
    expect(diagnostics?.ignoredNonQrCodeCount, 1);
    expect(diagnostics?.exposesRawPayload, isFalse);

    final safeText = diagnostics?.toSafeMap().toString() ?? '';
    expect(safeText, isNot(contains(leftPayload)));
    expect(safeText, isNot(contains(rightPayload)));
    expect(safeText, isNot(contains('private-non-qr-value')));
  });

  test('one image with left and right QR becomes a review pair', () async {
    final coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: NativeInvoiceQrDecoder(
        analyzer: const _FakeAnalyzer(
          <String, InvoiceQrImageAnalysis>{
            '/tmp/pair.jpg': InvoiceQrImageAnalysis(
              barcodes: <InvoiceQrDecodedBarcode>[
                InvoiceQrDecodedBarcode(
                  format: InvoiceQrDecodedFormat.qrCode,
                  rawValue: leftPayload,
                ),
                InvoiceQrDecodedBarcode(
                  format: InvoiceQrDecodedFormat.qrCode,
                  rawValue: rightPayload,
                ),
              ],
            ),
          },
        ),
      ),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/pair.jpg', 'pair.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.qrCandidate);
    expect(result.routingResult?.pairs.single.isComplete, isTrue);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.decoderDiagnostics.single.acceptedPayloadCount, 2);
  });

  test('separate images are decoded and paired before review', () async {
    final coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: NativeInvoiceQrDecoder(
        analyzer: const _FakeAnalyzer(
          <String, InvoiceQrImageAnalysis>{
            '/tmp/left.jpg': InvoiceQrImageAnalysis(
              barcodes: <InvoiceQrDecodedBarcode>[
                InvoiceQrDecodedBarcode(
                  format: InvoiceQrDecodedFormat.qrCode,
                  rawValue: leftPayload,
                ),
              ],
            ),
            '/tmp/right.jpg': InvoiceQrImageAnalysis(
              barcodes: <InvoiceQrDecodedBarcode>[
                InvoiceQrDecodedBarcode(
                  format: InvoiceQrDecodedFormat.qrCode,
                  rawValue: rightPayload,
                ),
              ],
            ),
          },
        ),
      ),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/left.jpg', 'left.jpg'),
        _image('/tmp/right.jpg', 'right.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.qrCandidate);
    expect(result.routingResult?.pairs.single.left.fileName, 'left.jpg');
    expect(result.routingResult?.pairs.single.right?.fileName, 'right.jpg');
    expect(result.decoderDiagnostics, hasLength(2));
  });

  test('no detected QR remains a local OCR fallback', () async {
    final coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: NativeInvoiceQrDecoder(
        analyzer: const _FakeAnalyzer(
          <String, InvoiceQrImageAnalysis>{
            '/tmp/text.jpg': InvoiceQrImageAnalysis(
              barcodes: <InvoiceQrDecodedBarcode>[],
            ),
          },
        ),
      ),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/text.jpg', 'text.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.ocrFallback);
    expect(result.routingResult?.shouldRunTraditionalOcr, isTrue);
    expect(result.decoderDiagnostics.single.detectedCodeCount, 0);
    expect(result.usedNetwork, isFalse);
  });

  test('native analyzer failure is preserved without leaking error text', () async {
    final coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: NativeInvoiceQrDecoder(
        analyzer: const _FakeAnalyzer(
          <String, InvoiceQrImageAnalysis>{},
          failingReferences: <String>{'/tmp/private.jpg'},
        ),
      ),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/private.jpg', 'private.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.decoderFailed);
    expect(result.failedImageReferences, <String>['/tmp/private.jpg']);
    expect(result.decoderDiagnostics.single.failed, isTrue);
    expect(result.decoderDiagnostics.single.failureCode, isNotEmpty);
    expect(
      result.decoderDiagnostics.single.toSafeMap().toString(),
      isNot(contains('encrypted-secret')),
    );
  });
}

ImageCaptureStagingItem _image(String reference, String fileName) {
  return ImageCaptureStagingItem(
    id: reference,
    intent: DailyCaptureIntent.invoice,
    source: ImageCaptureStagingSource.gallery,
    localReference: reference,
    fileName: fileName,
    status: ImageCaptureStagingStatus.pendingReview,
    createdAt: DateTime.utc(2026, 7, 5),
  );
}

class _FakeAnalyzer implements InvoiceQrImageAnalyzer {
  const _FakeAnalyzer(
    this.analysisByReference, {
    this.failingReferences = const <String>{},
  });

  final Map<String, InvoiceQrImageAnalysis> analysisByReference;
  final Set<String> failingReferences;

  @override
  Future<InvoiceQrImageAnalysis> analyze(String localReference) async {
    if (failingReferences.contains(localReference)) {
      throw StateError('encrypted-secret');
    }
    return analysisByReference[localReference] ??
        const InvoiceQrImageAnalysis(
          barcodes: <InvoiceQrDecodedBarcode>[],
        );
  }
}
