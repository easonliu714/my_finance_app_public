import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app root installs route-independent invoice award wake capture', () {
    final app = File('lib/app.dart').readAsStringSync();
    final coordinator = File(
      'lib/features/invoice/invoice_award_app_lifecycle_coordinator.dart',
    ).readAsStringSync();

    expect(app, contains('InvoiceAwardAppLifecycleCoordinator('));
    expect(coordinator, contains('WidgetsBindingObserver'));
    expect(coordinator, contains('AppLifecycleState.resumed'));
    expect(coordinator, contains('captureNativeWakeForForeground()'));
    expect(coordinator, contains('SharedPreferences.getInstance()'));

    // App-wide lifecycle capture is marker-only. It must not create a second
    // official acquisition/network stack.
    expect(coordinator, isNot(contains('package:http/http.dart')));
    expect(coordinator, isNot(contains('HttpClient')));
    expect(coordinator, isNot(contains('MinistryOfFinance')));
    expect(coordinator, isNot(contains('Navigator.')));
    expect(coordinator, isNot(contains('context.push')));
  });

  test('pending wake is cleared only when canonical refresh attempt starts', () {
    final scheduler = File(
      'lib/features/invoice/invoice_award_runtime_scheduler.dart',
    ).readAsStringSync();
    expect(scheduler, contains('markPendingForegroundCatchUp'));
    expect(scheduler, contains('clearPendingForegroundCatchUp'));
    expect(
      scheduler,
      contains('await clearPendingForegroundCatchUp();'),
    );
    expect(
      scheduler,
      contains('if (!state.automaticRefreshConsented)'),
    );
  });
}
