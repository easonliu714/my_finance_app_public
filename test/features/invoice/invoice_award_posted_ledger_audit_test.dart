import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_income_posting_service.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_posted_ledger_audit.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const audit = InvoiceAwardPostedLedgerAudit();
  final credited = DateTime.utc(2026, 10, 9, 1);
  final confirmed = DateTime.utc(2026, 10, 9, 2);
  final proposal = InvoiceAwardPayoutBookkeepingProposal(
    invoiceIdentity: 'candidate-123',
    awardPeriodId: '115-05-06',
    prizeTier: 'cloud-500',
    grossAmount: 500,
    localAccountId: 'bank-account-1',
    externalRemittanceEligibleAt: DateTime.utc(2026, 8, 5, 16),
    officialDatasetFingerprint: 'a' * 64,
    parserRuleVersion: 'test-rule',
  );
  final receipt = InvoiceAwardRemittanceReceiptEvidence(
    proposalKey: proposal.idempotencyKey,
    awardPeriodId: proposal.awardPeriodId,
    localAccountId: proposal.localAccountId,
    prizeTier: proposal.prizeTier,
    grossAmount: proposal.grossAmount,
    officialFingerprint: proposal.officialDatasetFingerprint,
    receivedAtUtc: credited,
    confirmedAtUtc: confirmed,
  );

  TransactionRecord posted() => TransactionRecord(
        id: InvoiceAwardFormalIncomePostingService.stableRecordId(proposal),
        type: TransactionType.income,
        amount: 500,
        category: '發票兌獎',
        occurredAt: credited.toLocal(),
        accountName: '測試銀行',
        memberName: '自己',
        merchantName: '',
        tagName: '',
        note: '發票獎金入帳；期別=115-05-06；'
            '獎別=cloud-500；'
            '來源SHA256=${'a' * 64}；'
            '候選=candidate-123；'
            '手動銀行收款確認（非銀行API驗證）',
        currency: CurrencyCode.twd,
      );

  InvoiceAwardPostedLedgerAuditStatus status(
    TransactionRecord? record, {
    InvoiceAwardRemittanceReceiptEvidence? evidence,
    String expectedAccountName = '測試銀行',
  }) =>
      audit
          .evaluate(
            proposal: proposal,
            receipt: evidence ?? receipt,
            ledgerRecord: record,
            expectedAccountName: expectedAccountName,
          )
          .status;

  test('canonical matching posted entry is local-only, never bank verified', () {
    final result = audit.evaluate(
      proposal: proposal,
      receipt: receipt,
      ledgerRecord: posted(),
      expectedAccountName: '測試銀行',
    );
    expect(result.status, InvoiceAwardPostedLedgerAuditStatus.postedLocalOnly);
    expect(result.isLocallyConsistent, isTrue);
    expect(result.isBankVerified, isFalse);
    expect(result.requiresReview, isFalse);
  });

  test('missing ledger row does not trigger posting or imply settlement', () {
    expect(status(null),
        InvoiceAwardPostedLedgerAuditStatus.missingLedgerEntry);
  });

  test('different stable transaction id is rejected', () {
    expect(
      status(posted().copyWith(id: 'unrelated-transaction')),
      InvoiceAwardPostedLedgerAuditStatus.transactionIdentityMismatch,
    );
  });

  test('expense or non-TWD record is not an eligible prize credit', () {
    expect(
      status(posted().copyWith(type: TransactionType.expense)),
      InvoiceAwardPostedLedgerAuditStatus.transactionTypeMismatch,
    );
    expect(
      status(posted().copyWith(currency: CurrencyCode.usd)),
      InvoiceAwardPostedLedgerAuditStatus.transactionTypeMismatch,
    );
  });

  test('amount and destination-account drift require manual review', () {
    expect(
      status(posted().copyWith(amount: 700)),
      InvoiceAwardPostedLedgerAuditStatus.amountMismatch,
    );
    expect(
      status(posted(), expectedAccountName: '其他銀行'),
      InvoiceAwardPostedLedgerAuditStatus.destinationAccountMismatch,
    );
  });

  test('receipt date mismatch remains evidence, never a ledger edit', () {
    expect(
      status(posted().copyWith(occurredAt: DateTime.utc(2026, 10, 10))),
      InvoiceAwardPostedLedgerAuditStatus.receiptDateMismatch,
    );
  });

  test('altered official fingerprint fails local provenance parity', () {
    expect(
      status(posted().copyWith(note: 'unrelated')),
      InvoiceAwardPostedLedgerAuditStatus.provenanceMismatch,
    );
  });

  test('invalid receipt and unknown destination fail closed', () {
    final stale = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: receipt.proposalKey,
      awardPeriodId: receipt.awardPeriodId,
      localAccountId: 'wrong-account-id',
      prizeTier: receipt.prizeTier,
      grossAmount: receipt.grossAmount,
      officialFingerprint: receipt.officialFingerprint,
      receivedAtUtc: credited,
      confirmedAtUtc: confirmed,
    );
    expect(
      status(posted(), evidence: stale),
      InvoiceAwardPostedLedgerAuditStatus.invalidEvidence,
    );
    expect(
      status(posted(), expectedAccountName: ''),
      InvoiceAwardPostedLedgerAuditStatus.invalidEvidence,
    );
  });
}
