import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app root owns best-effort award foreground catch-up', () {
    final app = File('lib/app.dart').readAsStringSync();
    expect(app, contains('with WidgetsBindingObserver'));
    expect(app, contains('AppLifecycleState.resumed'));
    expect(
      app,
      contains('runProductionInvoiceAwardForegroundCatchUp()'),
    );
    expect(app, contains('_catchUpDispatchActive'));
  });

  test('manual and automatic refresh share one process lease', () {
    final manual = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    final automatic = File(
      'lib/features/invoice/invoice_award_automatic_refresh_runtime.dart',
    ).readAsStringSync();

    expect(
      manual,
      contains('InvoiceAwardRefreshProcessLease.tryAcquire()'),
    );
    expect(
      manual,
      contains('InvoiceAwardRefreshProcessLease.release()'),
    );
    expect(
      automatic,
      contains('InvoiceAwardRefreshProcessLease.tryAcquire()'),
    );
    expect(
      automatic,
      contains('InvoiceAwardRefreshProcessLease.release()'),
    );
  });
}
