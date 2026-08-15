import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_live_adaptive_overlay.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_adaptive_page.dart';

void main() {
  test('wide guide preserves neutral camera field of view', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.wide,
        minZoom: 1,
        maxZoom: 8,
      ),
      1,
    );
  });

  test('narrow Traditional guide is visual-only and preserves neutral zoom', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.narrowTall,
        minZoom: 1,
        maxZoom: 8,
      ),
      1,
    );
  });

  test('guide-only neutral target respects a physical camera minimum', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.narrowTall,
        minZoom: 1.2,
        maxZoom: 4,
      ),
      1.2,
    );
  });

  test('guide-only neutral target respects a physical camera maximum', () {
    expect(
      resolveInvoiceAdaptiveCameraZoom(
        mode: InvoiceReceiptFrameMode.narrowTall,
        minZoom: 0.5,
        maxZoom: 0.8,
      ),
      0.8,
    );
  });
}
