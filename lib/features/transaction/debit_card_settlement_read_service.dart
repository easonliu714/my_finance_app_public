import 'package:sqflite/sqflite.dart';

import '../account/account_record.dart';
import 'debit_card_settlement.dart';
import 'debit_card_settlement_presentation.dart';
import 'transaction_record.dart';
import 'transaction_type.dart';

class DebitCardSettlementReadException implements Exception {
  const DebitCardSettlementReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DebitCardSettlementReadService {
  const DebitCardSettlementReadService({
    required this.databaseProvider,
    this.clock = const DebitCardSettlementPresentationClock(),
  });

  final Future<DatabaseExecutor> Function() databaseProvider;
  final DebitCardSettlementPresentationClock clock;

  Future<List<DebitCardSettlementPresentation>> loadForAccount(
    AccountRecord account, {
    DateTime? now,
  }) async {
    final normalizedNow = (now ?? DateTime.now()).toUtc();
    final db = await databaseProvider();
    switch (account.type) {
      case AccountType.debitCard:
        return _load(
          db,
          where: 'debit_card_account_id = ? AND status = ?',
          whereArgs: <Object?>[
            account.id,
            DebitCardSettlementStatus.pending.name,
          ],
          now: normalizedNow,
        );
      case AccountType.bank:
        return _load(
          db,
          where: 'linked_bank_account_id = ? AND status = ?',
          whereArgs: <Object?>[
            account.id,
            DebitCardSettlementStatus.pending.name,
          ],
          now: normalizedNow,
        );
      default:
        return const <DebitCardSettlementPresentation>[];
    }
  }

  Future<List<DebitCardSettlementPresentation>> loadAllPending({
    DateTime? now,
  }) async {
    final db = await databaseProvider();
    return _load(
      db,
      where: 'status = ?',
      whereArgs: <Object?>[DebitCardSettlementStatus.pending.name],
      now: (now ?? DateTime.now()).toUtc(),
    );
  }

  Future<List<DebitCardSettlementPresentation>> _load(
    DatabaseExecutor db, {
    required String where,
    required List<Object?> whereArgs,
    required DateTime now,
  }) async {
    final settlementRows = await db.query(
      'debit_card_settlements',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'expected_settlement_date ASC, authorized_at ASC, id ASC',
    );
    final result = <DebitCardSettlementPresentation>[];
    for (final row in settlementRows) {
      final settlement = DebitCardPendingSettlement.fromMap(row);
      final debitCard = await _requireAccount(
        db,
        settlement.debitCardAccountId,
        role: '簽帳金融卡',
      );
      final linkedBank = await _requireAccount(
        db,
        settlement.linkedBankAccountId,
        role: '綁定銀行',
      );
      final transaction = await _requireTransaction(
        db,
        settlement.transactionId,
      );
      _validateRelations(
        settlement: settlement,
        debitCard: debitCard,
        linkedBank: linkedBank,
        transaction: transaction,
      );
      result.add(
        DebitCardSettlementPresentation(
          settlement: settlement,
          debitCardAccount: debitCard,
          linkedBankAccount: linkedBank,
          transaction: transaction,
          status: clock.classify(settlement, now: now),
        ),
      );
    }
    return List<DebitCardSettlementPresentation>.unmodifiable(result);
  }

  Future<AccountRecord> _requireAccount(
    DatabaseExecutor db,
    String accountId, {
    required String role,
  }) async {
    final rows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw DebitCardSettlementReadException(
        '$role帳戶不存在：$accountId',
      );
    }
    return AccountRecord.fromMap(rows.single);
  }

  Future<TransactionRecord> _requireTransaction(
    DatabaseExecutor db,
    String transactionId,
  ) async {
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[transactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw DebitCardSettlementReadException(
        '待扣款來源交易不存在：$transactionId',
      );
    }
    return TransactionRecord.fromMap(rows.single);
  }

  void _validateRelations({
    required DebitCardPendingSettlement settlement,
    required AccountRecord debitCard,
    required AccountRecord linkedBank,
    required TransactionRecord transaction,
  }) {
    if (debitCard.type != AccountType.debitCard) {
      throw DebitCardSettlementReadException(
        '待扣款 ${settlement.id} 的來源帳戶不是簽帳金融卡。',
      );
    }
    if (linkedBank.type != AccountType.bank) {
      throw DebitCardSettlementReadException(
        '待扣款 ${settlement.id} 的扣款帳戶不是銀行帳戶。',
      );
    }
    if (debitCard.currency != settlement.currency ||
        linkedBank.currency != settlement.currency ||
        transaction.currency != settlement.currency) {
      throw DebitCardSettlementReadException(
        '待扣款 ${settlement.id} 的帳戶或交易幣別不一致。',
      );
    }
    if (transaction.type != TransactionType.expense) {
      throw DebitCardSettlementReadException(
        '待扣款 ${settlement.id} 的來源交易不是支出。',
      );
    }
    if (transaction.currency.roundAmount(transaction.amount) !=
        settlement.currency.roundAmount(settlement.amount)) {
      throw DebitCardSettlementReadException(
        '待扣款 ${settlement.id} 的金額與來源交易不一致。',
      );
    }
  }
}
