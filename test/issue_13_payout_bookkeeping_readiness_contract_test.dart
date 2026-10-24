import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payout readiness runtime has zero formal transaction write authority',
      () {
    final source = File(
      'lib/features/invoice/invoice_award_payout_bookkeeping_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('automaticBookkeepingEnabled'));
    expect(source, contains('externalMofRemittanceConfigured'));
    expect(source, contains('localAccountId'));
    expect(source, contains('cloudEligibilityConfirmationRequired'));
    expect(source, contains('InvoiceAwardPayoutBookkeepingProposalBuilder'));
    expect(source, isNot(contains('ProductionDatabaseCoordinator')));
    expect(source, isNot(contains('INSERT INTO transactions')));
    expect(source, isNot(contains('upsertTransaction')));
    expect(source, isNot(contains('deleteTransaction')));
  });
}
