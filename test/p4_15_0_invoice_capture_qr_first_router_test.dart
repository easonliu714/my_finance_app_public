import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_qr_first_router.dart';

void main() {
  test('local QR success creates review candidate without network', () async {
    final router = InvoiceCaptureQrFirstRouter(
      decoder: const _Decoder(<String>[_validLeftQr]),
      idFactory: () => 'qr-candidate-1',
      clock: () => DateTime.utc(2026, 7, 4, 17),
    );

    final result = await router.route(_image());

    expect(result.status, InvoiceCaptureQrRouteStatus.localQrCandidate);
    expect(result.usedNetwork, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.stagingCandidate?.id, 'qr-candidate-1');
    expect(result.stagingCandidate?.invoiceNumber, 'AB12345678');
    expect(result.stagingCandidate?.totalAmount, 120);
    expect(result.stagingCandidate?.note, contains('invoice.jpg'));
  });

  test('no local QR offers only a later fallback', () async {
    const router = InvoiceCaptureQrFirstRouter(
      decoder: _Decoder(<String>[]),
    );

    final result = await router.route(_image());

    expect(result.status, InvoiceCaptureQrRouteStatus.noQrFound);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.mayOfferExternalFallback, isTrue);
    expect(result.usedNetwork, isFalse);
  });

  test('invalid QR remains blocked for manual review', () async {
    const router = InvoiceCaptureQrFirstRouter(
      decoder: _Decoder(<String>['invalid']),
    );

    final result = await router.route(_image());

    expect(result.status, InvoiceCaptureQrRouteStatus.localQrInvalid);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.parseResult?.hasErrors, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('decoder exception preserves review-first state', () async {
    const router = InvoiceCaptureQrFirstRouter(
      decoder: _FailingDecoder(),
    );

    final result = await router.route(_image());

    expect(result.status, InvoiceCaptureQrRouteStatus.decoderFailed);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.usedNetwork, isFalse);
  });
}

ImageCaptureStagingItem _image() {
  return ImageCaptureStagingItem(
    id: 'image-1',
    intent: DailyCaptureIntent.invoice,
    source: ImageCaptureStagingSource.gallery,
    localReference: 'local-invoice.jpg',
    fileName: 'invoice.jpg',
    status: ImageCaptureStagingStatus.pendingReview,
    createdAt: DateTime.utc(2026, 7, 4, 17),
  );
}

const String _validLeftQr =
    'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

class _Decoder implements LocalInvoiceQrDecoder {
  const _Decoder(this.payloads);

  final List<String> payloads;

  @override
  Future<List<String>> decodeLocalImage(String localReference) async => payloads;
}

class _FailingDecoder implements LocalInvoiceQrDecoder {
  const _FailingDecoder();

  @override
  Future<List<String>> decodeLocalImage(String localReference) {
    throw StateError('decoder unavailable');
  }
}
