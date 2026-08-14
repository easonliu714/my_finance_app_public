import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_qr_first_router.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';

void main() {
  const validLeftQr =
      'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

  test('automatic mode produces a local QR review candidate', () async {
    const coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: _Decoder(<String, List<String>>{
        '/tmp/invoice.jpg': <String>[validLeftQr, '**detail'],
      }),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/invoice.jpg', 'invoice.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.qrCandidate);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.routingResult?.pairs.single.isComplete, isTrue);
    expect(result.usedNetwork, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('separate left and right images are decoded before pairing', () async {
    const coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: _Decoder(<String, List<String>>{
        '/tmp/left.jpg': <String>[validLeftQr],
        '/tmp/right.jpg': <String>['**detail'],
      }),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/left.jpg', 'left.jpg'),
        _image('/tmp/right.jpg', 'right.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.qrCandidate);
    expect(result.routingResult?.pairs.single.right?.fileName, 'right.jpg');
  });

  test('automatic mode falls back to OCR when no QR is found', () async {
    const coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: _Decoder(<String, List<String>>{
        '/tmp/text.jpg': <String>[],
      }),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/text.jpg', 'text.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.ocrFallback);
    expect(result.routingResult?.shouldRunTraditionalOcr, isTrue);
  });

  test('QR-only mode does not silently switch to OCR', () async {
    const coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: _Decoder(<String, List<String>>{
        '/tmp/no-qr.jpg': <String>[],
      }),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/no-qr.jpg', 'no-qr.jpg'),
      ],
      mode: InvoiceLocalRecognitionRequestMode.qrOnly,
    );

    expect(
      result.status,
      InvoiceLocalRecognitionStatus.manualQrDesignation,
    );
    expect(result.requiresManualQrDesignation, isTrue);
  });

  test('partial decoder failure preserves successful evidence', () async {
    const coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: _Decoder(
        <String, List<String>>{
          '/tmp/left.jpg': <String>[validLeftQr],
        },
        failingReferences: <String>{'/tmp/broken.jpg'},
      ),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/left.jpg', 'left.jpg'),
        _image('/tmp/broken.jpg', 'broken.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.qrCandidate);
    expect(result.failedImageReferences, <String>['/tmp/broken.jpg']);
    expect(result.message, contains('另有 1 張影像解碼失敗'));
  });

  test('all decoder failures fail closed', () async {
    const coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: _Decoder(
        <String, List<String>>{},
        failingReferences: <String>{'/tmp/a.jpg', '/tmp/b.jpg'},
      ),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[
        _image('/tmp/a.jpg', 'a.jpg'),
        _image('/tmp/b.jpg', 'b.jpg'),
      ],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.decoderFailed);
    expect(result.failedImageReferences, hasLength(2));
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('cancelled image input is rejected before decoding', () async {
    const coordinator = InvoiceLocalRecognitionCoordinator(
      decoder: _Decoder(<String, List<String>>{}),
    );
    final cancelled = ImageCaptureStagingItem(
      id: 'cancelled',
      intent: DailyCaptureIntent.invoice,
      source: ImageCaptureStagingSource.gallery,
      localReference: '/tmp/cancelled.jpg',
      fileName: 'cancelled.jpg',
      status: ImageCaptureStagingStatus.cancelled,
      createdAt: DateTime.utc(2026, 7, 5),
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[cancelled],
    );

    expect(result.status, InvoiceLocalRecognitionStatus.invalidInput);
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

class _Decoder implements LocalInvoiceQrDecoder {
  const _Decoder(
    this.payloadsByReference, {
    this.failingReferences = const <String>{},
  });

  final Map<String, List<String>> payloadsByReference;
  final Set<String> failingReferences;

  @override
  Future<List<String>> decodeLocalImage(String localReference) async {
    if (failingReferences.contains(localReference)) {
      throw StateError('decoder failed');
    }
    return payloadsByReference[localReference] ?? const <String>[];
  }
}
