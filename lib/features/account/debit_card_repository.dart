import 'package:sqflite/sqflite.dart';

import '../transaction/debit_card_settlement.dart';
import '../transaction/taiwan_business_calendar.dart';
import 'account_record.dart';
import 'debit_card_account_profile.dart';

class DebitCardRepository {
  const DebitCardRepository(this.db);

  final DatabaseExecutor db;

  Future<void> upsertProfile(DebitCardAccountProfile profile) async {
    final debitAccount = await _requireAccount(profile.debitCardAccountId);
    final bankAccount = await _requireAccount(profile.linkedBankAccountId);

    if (debitAccount.type != AccountType.debitCard) {
      throw StateError('Profile owner must be a debit-card account.');
    }
    DebitCardAccountProfile.link(
      debitCardAccountId: debitAccount.id,
      linkedBankAccount: bankAccount,
      debitCardCurrency: debitAccount.currency,
      settlementBusinessDays: profile.settlementBusinessDays,
      isEnabled: profile.isEnabled,
    );
    if (profile.currency != debitAccount.currency) {
      throw StateError('Profile currency must match the debit-card account.');
    }

    final map = profile.toMap()
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final updated = await db.update(
      'debit_card_profiles',
      map,
      where: 'debit_card_account_id = ?',
      whereArgs: <Object?>[profile.debitCardAccountId],
    );
    if (updated == 0) {
      await db.insert(
        'debit_card_profiles',
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<DebitCardAccountProfile?> getProfile(
    String debitCardAccountId,
  ) async {
    final rows = await db.query(
      'debit_card_profiles',
      where: 'debit_card_account_id = ?',
      whereArgs: <Object?>[debitCardAccountId.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : DebitCardAccountProfile.fromMap(rows.single);
  }

  Future<List<DebitCardAccountProfile>> listProfiles({
    bool enabledOnly = false,
  }) async {
    final rows = await db.query(
      'debit_card_profiles',
      where: enabledOnly ? 'is_enabled = 1' : null,
      orderBy: 'debit_card_account_id ASC',
    );
    return rows.map(DebitCardAccountProfile.fromMap).toList(growable: false);
  }

  Future<void> upsertSettlement(DebitCardPendingSettlement settlement) async {
    final profile = await getProfile(settlement.debitCardAccountId);
    if (profile == null) {
      throw StateError('Debit-card profile does not exist.');
    }
    if (!profile.isEnabled) {
      throw StateError('Debit-card profile is disabled.');
    }
    if (profile.linkedBankAccountId != settlement.linkedBankAccountId ||
        profile.currency != settlement.currency) {
      throw StateError('Settlement does not match the debit-card profile.');
    }

    final map = settlement.toMap()
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final updated = await db.update(
      'debit_card_settlements',
      map,
      where: 'id = ?',
      whereArgs: <Object?>[settlement.id],
    );
    if (updated == 0) {
      await db.insert(
        'debit_card_settlements',
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<DebitCardPendingSettlement?> getSettlement(String id) async {
    final rows = await db.query(
      'debit_card_settlements',
      where: 'id = ?',
      whereArgs: <Object?>[id.trim()],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DebitCardPendingSettlement.fromMap(rows.single);
  }

  Future<List<DebitCardPendingSettlement>> listSettlements({
    String? debitCardAccountId,
    DebitCardSettlementStatus? status,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (debitCardAccountId != null && debitCardAccountId.trim().isNotEmpty) {
      clauses.add('debit_card_account_id = ?');
      args.add(debitCardAccountId.trim());
    }
    if (status != null) {
      clauses.add('status = ?');
      args.add(status.name);
    }
    final rows = await db.query(
      'debit_card_settlements',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'expected_settlement_date ASC, authorized_at ASC',
    );
    return rows
        .map(DebitCardPendingSettlement.fromMap)
        .toList(growable: false);
  }

  Future<TaiwanBusinessCalendar> loadBusinessCalendar() async {
    final rows = await db.query(
      'taiwan_business_calendar_days',
      orderBy: 'calendar_date ASC',
    );
    if (rows.isEmpty) {
      throw const BusinessCalendarCoverageException(
        'Taiwan business-calendar reference table is empty.',
      );
    }

    final first = rows.first['calendar_date'] as String;
    final last = rows.last['calendar_date'] as String;
    final expectedDays = DateTime.parse(last)
            .difference(DateTime.parse(first))
            .inDays +
        1;
    if (rows.length != expectedDays) {
      throw BusinessCalendarCoverageException(
        'Taiwan business-calendar rows are not contiguous: '
        '${rows.length} / $expectedDays.',
      );
    }

    final closures = rows
        .where((row) {
          if ((row['is_business_day'] as num).toInt() != 0) return false;
          final date = DateTime.parse(row['calendar_date'] as String);
          return date.weekday != DateTime.saturday &&
              date.weekday != DateTime.sunday;
        })
        .map((row) => row['calendar_date'] as String)
        .toList(growable: false);
    final revisions = rows
        .map((row) => row['source_revision'] as String)
        .toSet()
        .toList()
      ..sort();

    return TaiwanBusinessCalendar(
      coverageStart: first,
      coverageEnd: last,
      nonBusinessDateKeys: closures,
      sourceRevision: revisions.join('+'),
    );
  }

  Future<AccountRecord> _requireAccount(String id) async {
    final rows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: <Object?>[id.trim()],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Account $id does not exist.');
    return AccountRecord.fromMap(rows.single);
  }
}
