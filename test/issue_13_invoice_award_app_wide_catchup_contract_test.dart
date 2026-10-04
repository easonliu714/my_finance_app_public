import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app-wide automatic runner composes canonical production authorities', () {
    final source = File(
      'lib/features/invoice/invoice_award_automatic_refresh_runner.dart',
    ).readAsStringSync();

    expect(source, contains('InvoiceAwardProductionRefreshController'));
    expect(
      source,
      contains('MinistryOfFinanceCloudAwardForegroundAcquisitionService'),
    );
    expect(source, contains('ExistingInvoiceAwardCandidateRepository'));
    expect(source, contains('cloudCandidateNumbersForAwardPeriod'));
    expect(source, contains('recordAttemptStarted'));
    expect(source, contains('recordAttemptFinished'));
    expect(source, contains('scheduler.reconcile'));
    expect(source, contains('InvoiceAwardRefreshProcessGate.tryAcquire()'));

    // The runner must compose existing production services rather than create
    // a second raw MOF transport/parser stack.
    expect(source, isNot(contains('Uri.parse(')));
    expect(source, isNot(contains('response.bodyBytes')));
    expect(source, isNot(contains('OfficialInvoiceAwardRawDocument(')));
    expect(source, isNot(contains('parse(')));
  });

  test('app-wide lifecycle coordinator executes due canonical catch-up', () {
    final source = File(
      'lib/features/invoice/invoice_award_app_lifecycle_coordinator.dart',
    ).readAsStringSync();

    expect(source, contains('captureNativeWakeForForeground()'));
    expect(source, contains('foregroundCatchUpDue('));
    expect(source, contains('InvoiceAwardRecentPeriodCatalog.defaultAt(now)'));
    expect(
      source,
      contains('InvoiceAwardCanonicalAutomaticRefreshRunner('),
    );
    expect(source, contains('await runner.refresh(selectedPeriod: selectedPeriod)'));

    // No navigation side effect and no duplicate transport implementation.
    expect(source, isNot(contains('Navigator.')));
    expect(source, isNot(contains('context.push')));
    expect(source, isNot(contains("package:http/http.dart")));
  });

  test('manual page and automatic runner share one process gate', () {
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    final runner = File(
      'lib/features/invoice/invoice_award_automatic_refresh_runner.dart',
    ).readAsStringSync();

    expect(page, contains('InvoiceAwardRefreshProcessGate.tryAcquire()'));
    expect(page, contains('InvoiceAwardRefreshProcessGate.release()'));
    expect(runner, contains('InvoiceAwardRefreshProcessGate.tryAcquire()'));
    expect(runner, contains('InvoiceAwardRefreshProcessGate.release()'));
    expect(page, isNot(contains('_processRefreshActive')));
  });
}
