import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4.20.24 user-observed remittance preflight remains nonposting', () {
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/features/invoice/invoice_award_remittance_receipt_evidence.dart',
    ).readAsStringSync();
    expect(page, contains('確認銀行獎金已實際入帳'));
    expect(page, contains('撤銷銀行入帳確認'));
    expect(page, contains('不是銀行官方驗證'));
    expect(runtime, contains('officialFingerprint'));
    expect(runtime, contains('receivedAtUtc'));
    expect(runtime, contains('isExternallyVerifiedBankCredit => false'));
    expect(runtime, contains('canAutomaticallyPostFormalIncome => false'));
    expect(runtime, isNot(contains('TransactionRepository')));
    expect(runtime, isNot(contains('INSERT INTO transactions')));
    expect(runtime, isNot(contains('upsertTransaction')));
  });
}
