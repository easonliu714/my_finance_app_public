import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_live_adaptive_overlay.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_adaptive_page.dart';

void main() {
  test('wide mode returns the neutral camera zoom when supported', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.wide,
        minZoom: 1,
        maxZoom: 8,
      ),
      1,
    );
  });

  test('narrow Traditional mode applies only the bounded 1.30x target', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.narrowTall,
        minZoom: 1,
        maxZoom: 8,
      ),
      1.30,
    );
  });

  test('narrow target is capped by the physical camera max zoom', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.narrowTall,
        minZoom: 1,
        maxZoom: 1.15,
      ),
      1.15,
    );
  });

  test('wide target never requests a zoom below the physical minimum', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.wide,
        minZoom: 1.2,
        maxZoom: 4,
      ),
      1.2,
    );
  });
}
