import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('transaction before-image round-trip preserves every stored field', () {
    final original = TransactionRecord(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: 328,
      category: '餐飲',
      occurredAt: DateTime(2026, 6, 18, 11, 45, 50),
      accountName: '信用卡',
      memberName: '',
      merchantName: '',
      tagName: '',
      note: '',
      currency: CurrencyCode.twd,
      exchangeRateToBase: 1,
    );

    final decoded = decodeTransactionBeforeImage(
      encodeTransactionBeforeImage(original),
    );

    expect(decoded.toMap(), original.toMap());
  });

  test('unknown transaction currency fails closed', () {
    final payload = jsonEncode(<String, Object?>{
      'version': canonicalCloudInvoicePayloadVersion,
      'transaction': <String, Object?>{
        'id': 'tx-1',
        'type': 'expense',
        'amount': 100,
        'category': '',
        'occurred_at': '2026-06-18T00:00:00.000',
        'account_name': '',
        'member_name': '',
        'merchant_name': '',
        'tag_name': '',
        'note': '',
        'currency_code': 'UNKNOWN',
        'exchange_rate_to_base': 1,
      },
    });

    expect(
      () => decodeTransactionBeforeImage(payload),
      throwsA(isA<FormatException>()),
    );
  });
}
