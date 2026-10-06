import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('winner notifications are user-controlled on production award surface', () {
    final source = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();

    expect(source, contains("Key('invoice_award_winning_notification_switch')"));
    expect(source, contains('中獎結果通知'));
    expect(source, contains('_setWinningNotificationsEnabled'));
    expect(source, contains('requestPermission()'));
    expect(source, contains('setWinningNotificationsEnabled(true)'));
    expect(source, contains('setWinningNotificationsEnabled(false)'));
    expect(source, contains('不顯示發票號碼、商家或記帳內容'));
  });

  test('automatic canonical refresh also delivers confirmed winners', () {
    final source = File(
      'lib/features/invoice/invoice_award_automatic_refresh_runner.dart',
    ).readAsStringSync();

    expect(source, contains('ExistingInvoiceAwardGeneralBatchMatcher'));
    expect(source, contains('ExistingInvoiceAwardCloudBatchMatcher'));
    expect(source, contains('InvoiceAwardWinningNotificationService'));
    expect(source, contains('deliverConfirmedWinners('));
    expect(source, contains('generalDatasetValidated: generalPromoted'));
    expect(source, contains('cloudDatasetValidated: cloudPromoted'));

    // No new raw MOF transport/parser is introduced by notification wiring.
    expect(source, isNot(contains('Uri.parse(')));
    expect(source, isNot(contains('response.bodyBytes')));
  });

  test('release authority advances for notification slice', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final metadata = File('lib/app_build_metadata.dart').readAsStringSync();

    expect(pubspec, contains('version: 4.20.21+479'));
    expect(metadata, contains("appVersion = '4.20.21+479'"));
    expect(metadata, contains("phase = 'issue-13-winning-notification-runtime-479'"));
  });
}
