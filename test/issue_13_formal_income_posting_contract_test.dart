import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_income_posting_service.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';

void main() {
  test('formal income source key is stable across restart or refresh', () {
    final p = InvoiceAwardPayoutBookkeepingProposal(
      invoiceIdentity: 'candidate-1',
      awardPeriodId: '115-05-06',
      prizeTier: 'cloud-500',
      grossAmount: 500,
      localAccountId: 'account-1',
      externalRemittanceEligibleAt: DateTime.utc(2026, 8, 6),
      officialDatasetFingerprint: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      parserRuleVersion: 'v1',
    );
    expect(InvoiceAwardFormalIncomePostingService.stableRecordId(p),
        'invoice-award-income:invoice-award:115-05-06:candidate-1:cloud-500');
  });

  test('posting is explicit-only, atomic, no replacement and no legacy backfill', () {
    final s = File(
      'lib/features/invoice/invoice_award_formal_income_posting_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    expect(s, contains('db.transaction<bool>'));
    expect(s, contains('ConflictAlgorithm.abort'));
    expect(s, isNot(contains('ConflictAlgorithm.replace')));
    expect(s, contains('receipt.matches(proposal)'));
    expect(s, contains('INVOICE_AWARD_POSTING_ACCOUNT_NAME_AMBIGUOUS'));
    expect(page, contains('_postConfirmedBankCredit'));
    expect(page, contains('確認新增正式發票兌獎收入'));
    expect(page, isNot(contains('_autoBackfillHistoricReceipts')));
  });
}
