import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4.20.23 production UI exposes payout bookkeeping preflight only', () {
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/features/invoice/invoice_award_payout_bookkeeping_runtime.dart',
    ).readAsStringSync();

    expect(page, contains('中獎獎金自動記帳準備'));
    expect(page, contains('獎金入帳帳戶（本機記帳用途）'));
    expect(page, contains('我已在財政部端設定自動匯款'));
    expect(page, contains('自動建立獎金待入帳候選'));
    expect(page, contains('本版仍不寫入正式交易'));
    expect(runtime, contains('externalRemittanceEligibleAt'));
    expect(runtime, contains('readyProposal'));
    expect(runtime, contains('cloudEligibilityRejected'));
    expect(runtime, contains('cloudEligibilityConfirmationRequired'));
    expect(runtime, isNot(contains('INSERT INTO transactions')));
    expect(runtime, isNot(contains('upsertTransaction')));
  });

  test('4.20.23 release identity is exact', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final metadata = File('lib/app_build_metadata.dart').readAsStringSync();

    expect(pubspec, contains('version: 4.20.25+483'));
    expect(metadata, contains("appVersion = '4.20.25+483'"));
    expect(
      metadata,
      contains("phase = 'issue-13-explicit-formal-award-income-483'"),
    );
  });
}
