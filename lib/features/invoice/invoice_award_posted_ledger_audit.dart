import '../account/account_record.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'invoice_award_formal_income_posting_service.dart';
import 'invoice_award_payout_bookkeeping_contract.dart';
import 'invoice_award_remittance_receipt_evidence.dart';

/// Read-only diagnostic status. This is not external-bank verification.
enum InvoiceAwardPostedLedgerAuditStatus {
  invalidEvidence,
  missingLedgerEntry,
  transactionIdentityMismatch,
  transactionTypeMismatch,
  amountMismatch,
  destinationAccountMismatch,
  receiptDateMismatch,
  provenanceMismatch,
  postedLocalOnly,
}

class InvoiceAwardPostedLedgerAuditResult {
  const InvoiceAwardPostedLedgerAuditResult(this.status);

  final InvoiceAwardPostedLedgerAuditStatus status;

  bool get isLocallyConsistent =>
      status == InvoiceAwardPostedLedgerAuditStatus.postedLocalOnly;

  /// An external bank statement is never inferred from a local ledger row.
  bool get isBankVerified => false;

  bool get requiresReview => !isLocallyConsistent;
}

/// Pure comparison against a caller-read canonical ledger record.
///
/// This service never writes SQLite, reads SharedPreferences, reverses a
/// receipt, or creates a replacement transaction. A mismatch is for review.
class InvoiceAwardPostedLedgerAudit {
  const InvoiceAwardPostedLedgerAudit();

  InvoiceAwardPostedLedgerAuditResult evaluate({
    required InvoiceAwardPayoutBookkeepingProposal proposal,
    required InvoiceAwardRemittanceReceiptEvidence receipt,
    required TransactionRecord? ledgerRecord,
    required String expectedAccountName,
  }) {
    if (!proposal.hasValidProvenance ||
        !receipt.matches(proposal) ||
        expectedAccountName.trim().isEmpty) {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.invalidEvidence,
      );
    }
    if (ledgerRecord == null) {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.missingLedgerEntry,
      );
    }
    if (ledgerRecord.id !=
        InvoiceAwardFormalIncomePostingService.stableRecordId(proposal)) {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.transactionIdentityMismatch,
      );
    }
    if (ledgerRecord.type != TransactionType.income ||
        ledgerRecord.currency != CurrencyCode.twd ||
        ledgerRecord.category != '發票兌獎') {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.transactionTypeMismatch,
      );
    }
    if (ledgerRecord.amount != proposal.grossAmount.toDouble()) {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.amountMismatch,
      );
    }
    if (ledgerRecord.accountName != expectedAccountName) {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.destinationAccountMismatch,
      );
    }
    if (!ledgerRecord.occurredAt.toUtc().isAtSameMomentAs(
          receipt.receivedAtUtc,
        )) {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.receiptDateMismatch,
      );
    }
    final note = ledgerRecord.note;
    if (!note.contains('期別=${proposal.awardPeriodId}；') ||
        !note.contains('獎別=${proposal.prizeTier}；') ||
        !note.contains('來源SHA256=${proposal.officialDatasetFingerprint}；') ||
        !note.contains('候選=${proposal.invoiceIdentity}；')) {
      return const InvoiceAwardPostedLedgerAuditResult(
        InvoiceAwardPostedLedgerAuditStatus.provenanceMismatch,
      );
    }
    return const InvoiceAwardPostedLedgerAuditResult(
      InvoiceAwardPostedLedgerAuditStatus.postedLocalOnly,
    );
  }
}
