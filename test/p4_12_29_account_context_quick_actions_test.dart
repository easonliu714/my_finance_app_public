import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/transaction_entry_page.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('transaction entry seed keeps normal and directional account values', () {
    const spending = TransactionEntrySeed(
      accountName: '信用卡・1234',
      initialType: TransactionType.expense,
    );
    expect(spending.accountName, '信用卡・1234');
    expect(spending.initialType, TransactionType.expense);

    const topUp = TransactionEntrySeed(
      fromAccountName: '銀行帳戶',
      toAccountName: '一卡通 Money',
      initialType: TransactionType.transfer,
    );
    expect(topUp.fromAccountName, '銀行帳戶');
    expect(topUp.toAccountName, '一卡通 Money');
    expect(topUp.initialType, TransactionType.transfer);
  });

  test('account quick actions remain wired to expense and transfer entry', () {
    final source = File(
      'lib/features/account/account_detail_page.dart',
    ).readAsStringSync();

    expect(source, contains("label: const Text('儲值')"));
    expect(source, contains('toAccountName: account.displayName'));
    expect(source, contains('initialType: TransactionType.transfer'));
    expect(source, contains('initialType: TransactionType.expense'));
    expect(source, contains('_openCreditCardPaymentFlow'));
  });

  test('package and private LAB versions remain aligned', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final versionLine = pubspec.firstWhere(
      (line) => line.startsWith('version:'),
    );
    final packageVersion = versionLine.split(':').last.trim();

    final labConfig = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',
    ).readAsStringSync();

    expect(
      labConfig,
      contains("validationVersion = '$packageVersion'"),
    );
  });
}
