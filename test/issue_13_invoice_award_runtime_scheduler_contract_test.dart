import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android award scheduler is best-effort marker only, with no network', () {
    final source = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/'
      'me/movenext/flutter_pdf_text/InvoiceAwardRefreshWakeReceiver.kt',
    ).readAsStringSync();

    expect(source, contains('AlarmManager'));
    expect(source, contains('setWindow'));
    expect(source, contains('BroadcastReceiver'));
    expect(source, contains('KEY_DUE_TARGET_MS'));
    expect(source, isNot(contains('HttpURLConnection')));
    expect(source, isNot(contains('OkHttp')));
    expect(source, isNot(contains('URL(')));
    expect(source, isNot(contains('startActivity')));
    expect(source, isNot(contains('startService')));
  });

  test('production page reuses canonical refresh for foreground catch-up', () {
    final source = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();

    expect(source, contains('InvoiceAwardRuntimeScheduler'));
    expect(source, contains('_runAutomaticCatchUpIfDue'));
    expect(source, contains('_refresh(automatic: true)'));

    final scheduler = File(
      'lib/features/invoice/invoice_award_runtime_scheduler.dart',
    ).readAsStringSync();
    expect(scheduler, contains('state.hasPendingForegroundCatchUp'));
    expect(scheduler, contains('if (!state.automaticRefreshConsented) return false;'));
    expect(source, contains('automaticRefreshConsented'));
    expect(source, contains('自動更新官方獎號'));
  });
}
