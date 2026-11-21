import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/production_database_coordinator.dart';
import '../account/account_record.dart';
import '../account/account_repository.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_ledger_refresh_signal.dart';
import '../transaction/transaction_type.dart';
import 'invoice_award_payout_bookkeeping_contract.dart';
import 'invoice_award_remittance_receipt_evidence.dart';

/// Explicit user-triggered, one-shot bank-receipt ledger credit.
/// Old v4.20.24 observations never invoke this service automatically.
class InvoiceAwardFormalIncomePostingService {
  const InvoiceAwardFormalIncomePostingService()
      : _isolatedDatabaseProvider = null,
        _isolatedAccountsProvider = null,
        _isolatedPreferencesProvider = null;

  // Only the isolated regression harness may supply dependencies. The
  // production constructor always uses the canonical account/SQLite stores;
  // neither constructor can bypass the Owner-C guard before store access.
  @visibleForTesting
  const InvoiceAwardFormalIncomePostingService.forIsolatedTest({
    required Future<Database> Function() databaseProvider,
    required Future<List<AccountRecord>> Function() accountsProvider,
    Future<SharedPreferences> Function()? preferencesProvider,
  })  : _isolatedDatabaseProvider = databaseProvider,
        _isolatedAccountsProvider = accountsProvider,
        _isolatedPreferencesProvider = preferencesProvider;

  final Future<Database> Function()? _isolatedDatabaseProvider;
  final Future<List<AccountRecord>> Function()? _isolatedAccountsProvider;
  final Future<SharedPreferences> Function()? _isolatedPreferencesProvider;

  Future<SharedPreferences> _preferences() =>
      _isolatedPreferencesProvider?.call() ?? SharedPreferences.getInstance();

  Future<Database> _database() =>
      _isolatedDatabaseProvider?.call() ??
      ProductionDatabaseCoordinator.instance.database;

  Future<List<AccountRecord>> _accounts() =>
      _isolatedAccountsProvider?.call() ??
      AccountRepository.instance.listAccounts();

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
    final db = await _database();
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
    // Reject before any account/SQLite access; preserve historical POSTED rows.
    if (proposal.isDeferredCloud500Prize) {
      throw StateError('CLOUD500_PRODUCTION_DEFERRED_OWNER_OPTION_C');
    }
    if (!authorizedAtUtc.isUtc ||
        authorizedAtUtc.isBefore(receipt.confirmedAtUtc) ||
        authorizedAtUtc.isBefore(receipt.receivedAtUtc) ||
        !receipt.matches(proposal) ||
        !proposal.hasValidProvenance) {
      throw StateError('INVOICE_AWARD_POSTING_EVIDENCE_INVALID');
    }
    // Service-level authority: a caller cannot bypass the UI modal with a
    // fabricated, revoked, or replaced receipt. Owner-C is rejected above,
    // before even opening preferences or the formal SQLite store.
    final preferences = await _preferences();
    final receiptRepository =
        InvoiceAwardRemittanceReceiptRepository(preferences);
    // Re-read external consent at each asynchronous posting boundary.
    // Cross-process CAS/TOCTOU and fsync remain independently unproven.
    Future<void> requireCurrentReceipt() async {
      if (!await receiptRepository.isCurrentObservationFresh(
          proposal: proposal, observation: receipt)) {
        throw StateError('INVOICE_AWARD_POSTING_RECEIPT_NOT_CURRENT');
      }
    }
    return receiptRepository.withCurrentObservationLease<bool>(
      proposal: proposal,
      observation: receipt,
      operation: () async {
        final accounts = await _accounts();
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
        final db = await _database();
        // Recheck after asynchronous account/database acquisition. This narrows
        // the revocation TOCTOU window; SharedPreferences and SQLite are still
        // separate stores and this is NOT cross-process atomicity.
        await requireCurrentReceipt();
        // The formal ledger owns the provider refresh event: publish only after
        // the SQLite transaction commits a genuinely new row, never for a
        // rejected Owner-C proposal or an idempotent duplicate.
        final inserted = await db.transaction<bool>((txn) async {
          final existing = await txn.query(
            'transactions',
            columns: const <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[record.id],
            limit: 1,
          );
          if (existing.isNotEmpty) return false;
          // Last in-isolate check immediately before the formal insert; a stale
          // receipt must not create a new row or emit a Provider refresh.
          await requireCurrentReceipt();
          // ABORT, not REPLACE: no overwrite on concurrency or repeated posts.
          await txn.insert(
            'transactions',
            record.toMap(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          return true;
        });
        if (inserted) TransactionLedgerRefreshSignal.instance.emit();
        return inserted;
      },
    );
  }
}
