import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification runtime is privacy-minimal and accounting-readonly', () {
    final source = File(
      'lib/features/invoice/invoice_award_notification_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('NotificationVisibility.private'));
    expect(source, contains('isConfirmedCloudNumberMatch'));
    expect(source, contains('skippedBecauseAuthorityIncomplete'));
    expect(source, isNot(contains('ProductionDatabaseCoordinator')));
    expect(source, isNot(contains('INSERT INTO transactions')));
    expect(source, isNot(contains('merchantName')));
    expect(source, isNot(contains('transactionAmount')));
  });

  test('runtime persists opt-in and idempotent sent keys locally', () {
    final source = File(
      'lib/features/invoice/invoice_award_notification_runtime.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('issue13_award_winning_notifications_enabled_v1'),
    );
    expect(
      source,
      contains('issue13_award_winning_notification_sent_keys_v1'),
    );
    expect(source, contains('markSent(selected.dedupeKey)'));
  });
}
