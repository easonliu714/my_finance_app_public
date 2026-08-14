import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P4.12.26 keeps screen awake only around explicit detail work', () {
    final guard = File(
      'lib/features/invoice/lab/official_invoice_detail_screen_awake_guard.dart',
    ).readAsStringSync();
    final sheet = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_sheet.dart',
    ).readAsStringSync();
    final retry = File(
      'lib/features/invoice/lab/official_invoice_detail_retry_page.dart',
    ).readAsStringSync();

    expect(guard, contains('WakelockPlus.enable()'));
    expect(guard, contains('WakelockPlus.disable()'));
    expect(sheet, contains('OfficialInvoiceDetailScreenAwakeGuard'));
    expect(sheet, contains('await _screenAwakeGuard.acquire()'));
    expect(sheet, contains('await _screenAwakeGuard.release()'));
    expect(retry, contains('OfficialInvoiceDetailScreenAwakeGuard'));
    expect(retry, contains('await _screenAwakeGuard.acquire()'));
    expect(retry, contains('await _screenAwakeGuard.release()'));
  });

  test('official detail script suspends timeout accounting while hidden', () {
    final script = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_script.dart',
    ).readAsStringSync();

    expect(script, contains('visibilitychange'));
    expect(script, contains('pagehide'));
    expect(script, contains('pageshow'));
    expect(script, contains('hostPaused'));
    expect(script, contains('pauseStartedAt'));
    expect(script, contains('pausedDurationMs'));
    expect(script, contains('activeElapsed'));
    final prohibitedToken = String.fromCharCodes(
      const <int>[100, 111, 99, 117, 109, 101, 110, 116, 46, 99, 111, 111, 107, 105, 101],
    );
    expect(script.toLowerCase(), isNot(contains(prohibitedToken)));
  });

  test('already-formal preflight section is count-bearing and collapsed', () {
    final page = File(
      'lib/features/invoice/lab/official_invoice_detail_draft_import_page.dart',
    ).readAsStringSync();

    expect(page, contains('alreadyFormalExpansionKey'));
    expect(page, contains('ExpansionTile'));
    expect(page, contains('initiallyExpanded: false'));
    expect(page, contains('已是正式交易（'));
    expect(page, contains('需要檢視時再展開'));
  });

  test('P4.12.26 version alignment and wakelock dependency remain pinned', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final config = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',
    ).readAsStringSync();
    final versionMatch = RegExp(
      r'^version:\s*([^\s]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(versionMatch, isNotNull);
    expect(pubspec, contains('wakelock_plus: 1.2.8'));
    expect(
      config,
      contains("validationVersion = '${versionMatch!.group(1)}'"),
    );
  });
}
