import 'package:sqflite/sqflite.dart';

import 'account_event_record.dart';
import 'account_record.dart';
import 'debit_card_account_profile.dart';
import 'debit_card_repository.dart';

class DebitCardAccountArchiveException implements Exception {
  const DebitCardAccountArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WalletTopUpAccountArchiveException implements Exception {
  const WalletTopUpAccountArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DebitCardAccountManagementService {
  const DebitCardAccountManagementService();

  Future<void> upsertAccountAndProfile(
    Database db, {
    required AccountRecord account,
    required DebitCardAccountProfile profile,
    required AccountEventRecord initialEvent,
  }) async {
    if (account.type != AccountType.debitCard) {
      throw StateError('Debit-card account save requires debitCard type.');
    }
    if (profile.debitCardAccountId != account.id) {
      throw StateError('Debit-card profile owner does not match the account.');
    }
    if (profile.currency != account.currency) {
      throw StateError('Debit-card profile currency does not match the account.');
    }
    if (account.initialBalance != 0) {
      throw StateError('Debit-card clearing account initial balance must be zero.');
    }

    await db.transaction((txn) async {
      final map = account.toMap()
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
      final updated = await txn.update(
        'accounts',
        map,
        where: 'id = ?',
        whereArgs: <Object?>[account.id],
      );
      if (updated == 0) {
        await txn.insert(
          'accounts',
          map,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await txn.insert(
        'account_events',
        initialEvent.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await DebitCardRepository(txn).upsertProfile(profile);
    });
  }

  Future<void> archiveAccount(Database db, String accountId) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: <Object?>[accountId.trim()],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Account $accountId does not exist.');
      }
      final account = AccountRecord.fromMap(rows.single);

      if (await _tableExists(txn, 'wallet_top_up_profiles')) {
        final targetLinks = await txn.query(
          'wallet_top_up_profiles',
          columns: const <String>['id'],
          where: 'target_account_id = ? AND is_enabled = 1',
          whereArgs: <Object?>[account.id],
          limit: 1,
        );
        if (targetLinks.isNotEmpty) {
          throw const WalletTopUpAccountArchiveException(
            '此電子錢包或儲值帳戶仍啟用低餘額儲值設定，請先停用後再封存。',
          );
        }
        final fundingLinks = await txn.query(
          'wallet_top_up_profiles',
          columns: const <String>['id'],
          where: 'funding_account_id = ? AND is_enabled = 1',
          whereArgs: <Object?>[account.id],
          limit: 1,
        );
        if (fundingLinks.isNotEmpty) {
          throw const WalletTopUpAccountArchiveException(
            '此帳戶仍是啟用中儲值設定的資金來源，請先停用或改綁後再封存。',
          );
        }
      }

      if (account.type == AccountType.bank) {
        final links = await txn.query(
          'debit_card_profiles',
          columns: const <String>['debit_card_account_id'],
          where: 'linked_bank_account_id = ? AND is_enabled = 1',
          whereArgs: <Object?>[account.id],
          limit: 1,
        );
        if (links.isNotEmpty) {
          throw const DebitCardAccountArchiveException(
            '此銀行帳戶仍綁定啟用中的簽帳金融卡，請先停用或改綁後再封存。',
          );
        }
      }

      if (account.type == AccountType.debitCard) {
        final pending = await txn.query(
          'debit_card_settlements',
          columns: const <String>['id'],
          where: 'debit_card_account_id = ? AND status = ?',
          whereArgs: <Object?>[account.id, 'pending'],
          limit: 1,
        );
        if (pending.isNotEmpty) {
          throw const DebitCardAccountArchiveException(
            '此簽帳金融卡仍有待扣款項目，完成、取消或標記失敗後才能封存。',
          );
        }
        await txn.update(
          'debit_card_profiles',
          <String, Object?>{
            'is_enabled': 0,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'debit_card_account_id = ?',
          whereArgs: <Object?>[account.id],
        );
      }

      await txn.update(
        'accounts',
        <String, Object?>{
          'is_archived': 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[account.id],
      );
    });
  }

  Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
