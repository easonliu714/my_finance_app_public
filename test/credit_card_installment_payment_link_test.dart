import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_payment_link.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('parseCreditCardInstallmentPaymentLink extracts plan and schedule from installment payment note', () {
    final record = _record(
      id: 'generated-tx-1',
      category: '信用卡分期付款',
      tagName: '信用卡分期',
      note: '信用卡分期繳款：Test Card 第 1/6 期；plan=plan-1; schedule=plan-1-1',
    );

    final link = parseCreditCardInstallmentPaymentLink(record);

    expect(link, isNotNull);
    expect(link!.planId, 'plan-1');
    expect(link.scheduleItemId, 'plan-1-1');
    expect(link.generatedTransactionId, 'generated-tx-1');
  });

  test('parseCreditCardInstallmentPaymentLink supports full-width semicolon separator', () {
    final record = _record(
      id: 'generated-tx-2',
      category: '信用卡分期付款',
      tagName: '信用卡分期',
      note: '信用卡分期繳款；plan=plan-2；schedule=plan-2-3',
    );

    final link = parseCreditCardInstallmentPaymentLink(record);

    expect(link, isNotNull);
    expect(link!.planId, 'plan-2');
    expect(link.scheduleItemId, 'plan-2-3');
    expect(link.generatedTransactionId, 'generated-tx-2');
  });

  test('parseCreditCardInstallmentPaymentLink ignores non-installment payment transactions', () {
    final record = _record(
      id: 'tx-normal',
      category: '日常',
      tagName: '生活',
      note: 'plan=plan-1; schedule=plan-1-1',
    );

    expect(parseCreditCardInstallmentPaymentLink(record), isNull);
  });

  test('parseCreditCardInstallmentPaymentLink returns null when note has no link data', () {
    final record = _record(
      id: 'generated-tx-3',
      category: '信用卡分期付款',
      tagName: '信用卡分期',
      note: '信用卡分期繳款',
    );

    expect(parseCreditCardInstallmentPaymentLink(record), isNull);
  });
}

TransactionRecord _record({required String id, required String category, required String tagName, required String note}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    amount: 2000,
    category: category,
    occurredAt: DateTime(2026, 5, 30),
    accountName: '銀行帳戶',
    memberName: '自己',
    merchantName: '信用卡A',
    tagName: tagName,
    note: note,
  );
}
