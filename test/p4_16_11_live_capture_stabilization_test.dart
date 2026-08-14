import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_stabilized_page.dart';

void main() {
  test('frozen identity gate normalizes printed separators only', () {
    expect(
      isFrozenInvoiceIdentityConsistent(
        liveInvoiceNumber: 'XY90000021',
        frozenInvoiceNumber: 'XY 9000-0021',
      ),
      isTrue,
    );
    expect(
      isFrozenInvoiceIdentityConsistent(
        liveInvoiceNumber: 'XY90000021',
        frozenInvoiceNumber: 'XY90000022',
      ),
      isFalse,
    );
    expect(
      isFrozenInvoiceIdentityConsistent(
        liveInvoiceNumber: '',
        frozenInvoiceNumber: '',
      ),
      isFalse,
    );
  });

  test('camera telemetry remains evidence-compatible without OCR text', () {
    final sample = InvoiceLiveCameraTelemetryEvidence(
      timestamp: DateTime.utc(2026, 8, 10, 15, 30),
      snapshot: const InvoiceLiveSnapshot(
        classification: InvoiceLiveClassification.traditional,
        invoiceNumber: 'XY90000021',
        stableObservations: 2,
        canFreeze: true,
      ),
      event: 'FROZEN_IDENTITY_CHECK',
      details: const <String, Object?>{
        'identityMatches': true,
        'focusLocked': true,
        'exposureLocked': true,
      },
    );

    final json = sample.toJson();
    expect(json['sampleType'], 'cameraTelemetry');
    expect(json['cameraEvent'], 'FROZEN_IDENTITY_CHECK');
    expect(json['rawLines'], isEmpty);
    expect(json['sellerTaxIdSource'], 'camera_telemetry');
    expect(
      (json['cameraDetails']! as Map<String, Object?>)['identityMatches'],
      isTrue,
    );
  });
}
