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
    expect(page, contains('自動準備僅產生待入帳候選；確認實際收款並再次明確授權後，才會新增正式收入。'));
    expect(runtime, contains('externalRemittanceEligibleAt'));
    expect(runtime, contains('readyProposal'));
    expect(runtime, contains('cloudEligibilityRejected'));
    expect(runtime, contains('cloudEligibilityConfirmationRequired'));
    expect(runtime, isNot(contains('INSERT INTO transactions')));
    expect(runtime, isNot(contains('upsertTransaction')));
  });

  test('current Issue #13 release identity is exact', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final metadata = File('lib/app_build_metadata.dart').readAsStringSync();

    expect(pubspec, contains('version: 4.20.36+494'));
    expect(metadata, contains("appVersion = '4.20.36+494'"));
    expect(
      metadata,
      contains("phase = 'issue-13-task-route-reattach-observer-494'"),
    );
  });
}
