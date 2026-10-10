import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../account/account_record.dart';
import '../account/account_repository.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'invoice_award_payout_bookkeeping_contract.dart';
import 'invoice_award_remittance_receipt_evidence.dart';

/// Explicit user-triggered, one-shot bank-receipt ledger credit.
/// Old v4.20.24 observations never invoke this service automatically.
class InvoiceAwardFormalIncomePostingService {
  const InvoiceAwardFormalIncomePostingService();

  static String stableRecordId(InvoiceAwardPayoutBookkeepingProposal p) =>
      'invoice-award-income:${p.idempotencyKey}';

  /// The canonical formal ledger is the only POSTED authority.
  /// Never infer POSTED from SharedPreferences receipt observations.
  Future<Set<String>> readPostedIds(
      Iterable<InvoiceAwardPayoutBookkeepingProposal> proposals) async {
    final ids = proposals
        .where((proposal) => proposal.hasValidProvenance)
        .map(stableRecordId)
        .toSet();
    if (ids.isEmpty) return <String>{};
    final db = await ProductionDatabaseCoordinator.instance.database;
    final posted = <String>{};
    for (final id in ids) {
      final rows = await db.query(
        'transactions',
        columns: const <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isNotEmpty) posted.add(id);
    }
    return posted;
  }

  Future<bool> post({
    required InvoiceAwardPayoutBookkeepingProposal proposal,
    required InvoiceAwardRemittanceReceiptEvidence receipt,
    required DateTime authorizedAtUtc,
  }) async {
    if (!authorizedAtUtc.isUtc ||
        authorizedAtUtc.isBefore(receipt.confirmedAtUtc) ||
        authorizedAtUtc.isBefore(receipt.receivedAtUtc) ||
        !receipt.matches(proposal) ||
        !proposal.hasValidProvenance) {
      throw StateError('INVOICE_AWARD_POSTING_EVIDENCE_INVALID');
    }
    final accounts = await AccountRepository.instance.listAccounts();
    final matches = accounts.where((a) =>
        a.id == proposal.localAccountId &&
        !a.isArchived &&
        a.currency == CurrencyCode.twd &&
        (a.type == AccountType.bank || a.type == AccountType.debitCard))
        .toList(growable: false);
    if (matches.length != 1) {
      throw StateError('INVOICE_AWARD_POSTING_ACCOUNT_UNAVAILABLE');
    }
    final account = matches.single;
    // The ledger uses displayName, so reject ambiguous account labels.
    if (accounts.where((a) =>
        !a.isArchived && a.displayName == account.displayName).length != 1) {
      throw StateError('INVOICE_AWARD_POSTING_ACCOUNT_NAME_AMBIGUOUS');
    }
    final record = TransactionRecord(
      id: stableRecordId(proposal),
      type: TransactionType.income,
      amount: proposal.grossAmount.toDouble(),
      category: '發票兌獎',
      occurredAt: receipt.receivedAtUtc.toLocal(),
      accountName: account.displayName,
      memberName: '自己',
      merchantName: '',
      tagName: '',
      note: '發票獎金入帳；期別=${proposal.awardPeriodId}；'
          '獎別=${proposal.prizeTier}；'
          '來源SHA256=${proposal.officialDatasetFingerprint}；'
          '候選=${proposal.invoiceIdentity}；'
          '手動銀行收款確認（非銀行API驗證）',
      currency: CurrencyCode.twd,
      exchangeRateToBase: 1,
    );
    final db = await ProductionDatabaseCoordinator.instance.database;
    return db.transaction<bool>((txn) async {
      final existing = await txn.query(
        'transactions',
        columns: const <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[record.id],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      // ABORT, not REPLACE: no overwrite on concurrency or repeated posts.
      await txn.insert(
        'transactions',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return true;
    });
  }
}
