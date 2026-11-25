import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4.20.27 distinguishes preparation, receipt and formal-posting consent',
      () {
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();

    // The receipt and final-consent dialogs now live in the shared UI module.
    final confirmation = File(
      'lib/features/invoice/invoice_award_formal_posting_confirmation.dart',
    ).readAsStringSync();

    expect(page, contains('requestInvoiceAwardReceivedAmount('));
    expect(page, contains('InvoiceAwardFormalPostingConfirmation().requestAndPost('));
    expect(page, contains('這項資格確認只會記錄在本機'));
    expect(confirmation, contains('正式入帳需要再次明確授權'));
    expect(page, contains('確認實際收款並再次明確授權後'));
    expect(page, contains('正式記帳仍須另行確認'));
    expect(page, contains('POSTED（已記帳）'));
    expect(page, contains('確認新增正式發票兌獎收入'));
    expect(confirmation, contains('確認新增正式發票兌獎收入'));
    expect(page, isNot(contains('本版仍不寫入正式交易')));
    expect(page, isNot(contains('本版只建立可稽核的待入帳候選')));
    expect(confirmation, isNot(contains('本版仍不寫入正式交易')));
    expect(confirmation, isNot(contains('本版只建立可稽核的待入帳候選')));
  });

  test('4.20.27 keeps ledger write/duplicate boundary unchanged', () {
    final service = File(
      'lib/features/invoice/invoice_award_formal_income_posting_service.dart',
    ).readAsStringSync();
    expect(service, contains('db.transaction<bool>'));
    expect(service, contains('ConflictAlgorithm.abort'));
    expect(service, isNot(contains('ConflictAlgorithm.replace')));
  });
}
