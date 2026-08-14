import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'account_record.dart';
import 'wallet_top_up_persistence.dart';
import 'wallet_top_up_recommendation.dart';

class WalletTopUpRepository {
  const WalletTopUpRepository(this.db);

  final DatabaseExecutor db;

  Future<StoredWalletTopUpProfile> upsertProfile(
    StoredWalletTopUpProfile profile, {
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();

    return _inTransaction((txn) async {
      final normalized = await _validateAndNormalizeProfile(
        txn,
        profile,
        timestamp,
      );
      final existingById = await _getProfile(txn, normalized.id);
      final conflictingTarget = await txn.query(
        'wallet_top_up_profiles',
        columns: const <String>['id'],
        where: 'target_account_id = ? AND id <> ?',
        whereArgs: <Object?>[normalized.targetAccountId, normalized.id],
        limit: 1,
      );
      if (conflictingTarget.isNotEmpty) {
        throw const WalletTopUpPersistenceException(
          WalletTopUpPersistenceErrorCode.profileIdentityMismatch,
          'A different profile already owns the target account.',
        );
      }

      final saved = normalized.copyWith(
        createdAt: existingById?.createdAt ?? timestamp,
        updatedAt: timestamp,
      );
      final updated = await txn.update(
        'wallet_top_up_profiles',
        saved.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[saved.id],
      );
      if (updated == 0) {
        await txn.insert(
          'wallet_top_up_profiles',
          saved.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      final eventType = _profileAuditEvent(existingById, saved);
      await _insertAudit(
        txn,
        eventType: eventType,
        profileId: saved.id,
        createdAt: timestamp,
        details: <String, Object?>{
          'target_account_id': saved.targetAccountId,
          'funding_account_id': saved.fundingAccountId,
          'currency_code': saved.currency.code,
          'amount_mode': saved.amountMode.name,
          'is_enabled': saved.isEnabled,
        },
      );
      return saved;
    });
  }

  Future<StoredWalletTopUpProfile?> getProfile(String id) {
    return _getProfile(db, id.trim());
  }

  Future<StoredWalletTopUpProfile?> getProfileForTargetAccount(
    String targetAccountId,
  ) async {
    final rows = await db.query(
      'wallet_top_up_profiles',
      where: 'target_account_id = ?',
      whereArgs: <Object?>[targetAccountId.trim()],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : StoredWalletTopUpProfile.fromMap(rows.single);
  }

  Future<List<StoredWalletTopUpProfile>> listProfiles({
    bool enabledOnly = false,
  }) async {
    final rows = await db.query(
      'wallet_top_up_profiles',
      where: enabledOnly ? 'is_enabled = 1' : null,
      orderBy: 'target_account_id ASC',
    );
    return rows
        .map(StoredWalletTopUpProfile.fromMap)
        .toList(growable: false);
  }

  Future<PersistedWalletTopUpSuggestionResult> persistSuggestion({
    required String profileId,
    required WalletTopUpSuggestion suggestion,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return _inTransaction((txn) async {
      final profile = await _requireProfile(txn, profileId);
      if (!profile.isEnabled) {
        throw const WalletTopUpRecommendationException(
          WalletTopUpRecommendationErrorCode.profileDisabled,
          'Disabled profiles cannot persist suggestions.',
        );
      }
      _requireSuggestionMatchesProfile(profile, suggestion);

      final existingRows = await txn.query(
        'wallet_top_up_suggestions',
        where: 'id = ?',
        whereArgs: <Object?>[suggestion.suggestionId],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existing = StoredWalletTopUpSuggestion.fromMap(
          existingRows.single,
        );
        if (!_sameDeterministicSuggestion(existing, suggestion, profile.id)) {
          throw const WalletTopUpPersistenceException(
            WalletTopUpPersistenceErrorCode.suggestionReplayConflict,
            'Suggestion ID replayed with a conflicting canonical payload.',
          );
        }
        return PersistedWalletTopUpSuggestionResult(
          suggestion: existing,
          replayed: true,
          supersededSuggestionIds: const <String>[],
        );
      }

      final pendingRows = await txn.query(
        'wallet_top_up_suggestions',
        where: 'profile_id = ? AND status = ? AND id <> ?',
        whereArgs: <Object?>[
          profile.id,
          WalletTopUpSuggestionStatus.pending.name,
          suggestion.suggestionId,
        ],
        orderBy: 'evaluated_at ASC, id ASC',
      );
      final supersededIds = <String>[];
      for (final row in pendingRows) {
        final previous = StoredWalletTopUpSuggestion.fromMap(row);
        await txn.update(
          'wallet_top_up_suggestions',
          <String, Object?>{
            'status': WalletTopUpSuggestionStatus.superseded.name,
            'updated_at': timestamp.toIso8601String(),
          },
          where: 'id = ? AND status = ?',
          whereArgs: <Object?>[
            previous.id,
            WalletTopUpSuggestionStatus.pending.name,
          ],
        );
        supersededIds.add(previous.id);
        await _insertAudit(
          txn,
          eventType: WalletTopUpAuditEventType.suggestionSuperseded,
          profileId: profile.id,
          suggestionId: previous.id,
          createdAt: timestamp,
          details: <String, Object?>{
            'replacement_suggestion_id': suggestion.suggestionId,
          },
        );
      }

      final stored = StoredWalletTopUpSuggestion.fromDomain(
        profileId: profile.id,
        suggestion: suggestion,
        createdAt: timestamp,
      );
      await txn.insert(
        'wallet_top_up_suggestions',
        stored.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _insertAudit(
        txn,
        eventType: WalletTopUpAuditEventType.suggestionCreated,
        profileId: profile.id,
        suggestionId: stored.id,
        createdAt: timestamp,
        details: <String, Object?>{
          'suggested_amount': stored.suggestedAmount,
          'funding_sufficient': stored.fundingSufficient,
          'funding_shortfall': stored.fundingShortfall,
        },
      );
      return PersistedWalletTopUpSuggestionResult(
        suggestion: stored,
        replayed: false,
        supersededSuggestionIds: List<String>.unmodifiable(supersededIds),
      );
    });
  }

  Future<DismissedWalletTopUpSuggestionResult> dismissSuggestion(
    String suggestionId, {
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return _inTransaction((txn) async {
      final suggestion = await _requireSuggestion(txn, suggestionId);
      if (suggestion.status == WalletTopUpSuggestionStatus.dismissed) {
        return DismissedWalletTopUpSuggestionResult(
          suggestion: suggestion,
          replayed: true,
        );
      }
      if (suggestion.status != WalletTopUpSuggestionStatus.pending) {
        throw const WalletTopUpPersistenceException(
          WalletTopUpPersistenceErrorCode.invalidSuggestionTransition,
          'Only pending suggestions can be dismissed.',
        );
      }

      final dismissed = suggestion.copyWith(
        status: WalletTopUpSuggestionStatus.dismissed,
        updatedAt: timestamp,
      );
      await txn.update(
        'wallet_top_up_suggestions',
        <String, Object?>{
          'status': dismissed.status.name,
          'updated_at': timestamp.toIso8601String(),
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object?>[
          dismissed.id,
          WalletTopUpSuggestionStatus.pending.name,
        ],
      );
      await _insertAudit(
        txn,
        eventType: WalletTopUpAuditEventType.suggestionDismissed,
        profileId: dismissed.profileId,
        suggestionId: dismissed.id,
        createdAt: timestamp,
      );
      return DismissedWalletTopUpSuggestionResult(
        suggestion: dismissed,
        replayed: false,
      );
    });
  }

  Future<StoredWalletTopUpSuggestion?> getSuggestion(String id) async {
    final rows = await db.query(
      'wallet_top_up_suggestions',
      where: 'id = ?',
      whereArgs: <Object?>[id.trim()],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : StoredWalletTopUpSuggestion.fromMap(rows.single);
  }

  Future<List<StoredWalletTopUpSuggestion>> listSuggestions({
    String? profileId,
    WalletTopUpSuggestionStatus? status,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (profileId != null && profileId.trim().isNotEmpty) {
      clauses.add('profile_id = ?');
      args.add(profileId.trim());
    }
    if (status != null) {
      clauses.add('status = ?');
      args.add(status.name);
    }
    final rows = await db.query(
      'wallet_top_up_suggestions',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'evaluated_at DESC, id ASC',
    );
    return rows
        .map(StoredWalletTopUpSuggestion.fromMap)
        .toList(growable: false);
  }

  Future<List<WalletTopUpAuditRecord>> listAudits({
    String? profileId,
    String? suggestionId,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (profileId != null && profileId.trim().isNotEmpty) {
      clauses.add('profile_id = ?');
      args.add(profileId.trim());
    }
    if (suggestionId != null && suggestionId.trim().isNotEmpty) {
      clauses.add('suggestion_id = ?');
      args.add(suggestionId.trim());
    }
    final rows = await db.query(
      'wallet_top_up_audits',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(WalletTopUpAuditRecord.fromMap).toList(growable: false);
  }

  Future<StoredWalletTopUpProfile> _validateAndNormalizeProfile(
    DatabaseExecutor executor,
    StoredWalletTopUpProfile profile,
    DateTime timestamp,
  ) async {
    if (profile.id.trim().isEmpty) {
      throw const WalletTopUpPersistenceException(
        WalletTopUpPersistenceErrorCode.profileIdentityMismatch,
        'Profile ID cannot be empty.',
      );
    }
    final target = await _requireAccount(
      executor,
      profile.targetAccountId,
      WalletTopUpPersistenceErrorCode.targetAccountNotFound,
    );
    final funding = await _requireAccount(
      executor,
      profile.fundingAccountId,
      WalletTopUpPersistenceErrorCode.fundingAccountNotFound,
    );
    final normalizedThreshold = profile.currency.roundAmount(profile.threshold);
    final normalizedTarget = profile.amountMode == WalletTopUpAmountMode.targetBalance
        ? profile.currency.roundAmount(profile.targetBalance)
        : 0.0;
    final normalizedFixed = profile.amountMode == WalletTopUpAmountMode.fixedAmount
        ? profile.currency.roundAmount(profile.fixedAmount)
        : 0.0;
    final normalized = profile.copyWith(
      id: profile.id.trim(),
      targetAccountId: profile.targetAccountId.trim(),
      fundingAccountId: profile.fundingAccountId.trim(),
      threshold: normalizedThreshold,
      targetBalance: normalizedTarget,
      fixedAmount: normalizedFixed,
      createdAt: profile.createdAt.toUtc(),
      updatedAt: timestamp,
    );

    const validator = WalletTopUpRecommendationService();
    validator.evaluate(
      WalletTopUpEvaluationInput(
        profile: WalletTopUpProfile(
          targetAccountId: normalized.targetAccountId,
          fundingAccountId: normalized.fundingAccountId,
          currency: normalized.currency,
          threshold: normalized.threshold,
          amountMode: normalized.amountMode,
          targetBalance: normalized.targetBalance,
          fixedAmount: normalized.fixedAmount,
          isEnabled: true,
          cooldown: normalized.cooldown,
        ),
        targetAccount: target,
        fundingAccount: funding,
        currentAvailableBalance: normalized.threshold,
        fundingAvailableBalance: 0,
        evaluatedAt: timestamp,
      ),
    );
    return normalized;
  }

  Future<AccountRecord> _requireAccount(
    DatabaseExecutor executor,
    String id,
    WalletTopUpPersistenceErrorCode errorCode,
  ) async {
    final rows = await executor.query(
      'accounts',
      where: 'id = ?',
      whereArgs: <Object?>[id.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw WalletTopUpPersistenceException(
        errorCode,
        'Account ${id.trim()} does not exist.',
      );
    }
    return AccountRecord.fromMap(rows.single);
  }

  Future<StoredWalletTopUpProfile?> _getProfile(
    DatabaseExecutor executor,
    String id,
  ) async {
    final rows = await executor.query(
      'wallet_top_up_profiles',
      where: 'id = ?',
      whereArgs: <Object?>[id.trim()],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : StoredWalletTopUpProfile.fromMap(rows.single);
  }

  Future<StoredWalletTopUpProfile> _requireProfile(
    DatabaseExecutor executor,
    String id,
  ) async {
    final profile = await _getProfile(executor, id);
    if (profile == null) {
      throw WalletTopUpPersistenceException(
        WalletTopUpPersistenceErrorCode.profileNotFound,
        'Wallet top-up profile ${id.trim()} does not exist.',
      );
    }
    return profile;
  }

  Future<StoredWalletTopUpSuggestion> _requireSuggestion(
    DatabaseExecutor executor,
    String id,
  ) async {
    final rows = await executor.query(
      'wallet_top_up_suggestions',
      where: 'id = ?',
      whereArgs: <Object?>[id.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw WalletTopUpPersistenceException(
        WalletTopUpPersistenceErrorCode.suggestionNotFound,
        'Wallet top-up suggestion ${id.trim()} does not exist.',
      );
    }
    return StoredWalletTopUpSuggestion.fromMap(rows.single);
  }

  void _requireSuggestionMatchesProfile(
    StoredWalletTopUpProfile profile,
    WalletTopUpSuggestion suggestion,
  ) {
    if (suggestion.targetAccountId != profile.targetAccountId ||
        suggestion.fundingAccountId != profile.fundingAccountId ||
        suggestion.currency != profile.currency ||
        suggestion.amountMode != profile.amountMode) {
      throw const WalletTopUpPersistenceException(
        WalletTopUpPersistenceErrorCode.suggestionProfileMismatch,
        'Suggestion does not match the persisted profile.',
      );
    }
  }

  bool _sameDeterministicSuggestion(
    StoredWalletTopUpSuggestion existing,
    WalletTopUpSuggestion suggestion,
    String profileId,
  ) {
    final currency = suggestion.currency;
    return existing.profileId == profileId &&
        existing.targetAccountId == suggestion.targetAccountId &&
        existing.fundingAccountId == suggestion.fundingAccountId &&
        existing.currency == currency &&
        existing.amountMode == suggestion.amountMode &&
        currency.roundAmount(existing.currentAvailableBalance) ==
            currency.roundAmount(suggestion.currentAvailableBalance) &&
        currency.roundAmount(existing.threshold) ==
            currency.roundAmount(suggestion.threshold) &&
        currency.roundAmount(existing.suggestedAmount) ==
            currency.roundAmount(suggestion.suggestedAmount);
  }

  WalletTopUpAuditEventType _profileAuditEvent(
    StoredWalletTopUpProfile? previous,
    StoredWalletTopUpProfile current,
  ) {
    if (previous == null) return WalletTopUpAuditEventType.profileCreated;
    if (!previous.isEnabled && current.isEnabled) {
      return WalletTopUpAuditEventType.profileEnabled;
    }
    if (previous.isEnabled && !current.isEnabled) {
      return WalletTopUpAuditEventType.profileDisabled;
    }
    return WalletTopUpAuditEventType.profileUpdated;
  }

  Future<void> _insertAudit(
    DatabaseExecutor executor, {
    required WalletTopUpAuditEventType eventType,
    required String profileId,
    required DateTime createdAt,
    String? suggestionId,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    final audit = WalletTopUpAuditRecord(
      id: _auditId(
        eventType: eventType,
        profileId: profileId,
        suggestionId: suggestionId,
        createdAt: createdAt,
      ),
      eventType: eventType,
      profileId: profileId,
      suggestionId: suggestionId,
      detailsJson: jsonEncode(details),
      createdAt: createdAt,
    );
    await executor.insert(
      'wallet_top_up_audits',
      audit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  String _auditId({
    required WalletTopUpAuditEventType eventType,
    required String profileId,
    required DateTime createdAt,
    String? suggestionId,
  }) {
    final subject = suggestionId ?? 'profile';
    return 'wallet-top-up-audit-${eventType.name}-$profileId-$subject-'
        '${createdAt.toUtc().microsecondsSinceEpoch}';
  }

  Future<T> _inTransaction<T>(
    Future<T> Function(DatabaseExecutor executor) action,
  ) async {
    if (db is Database) {
      return (db as Database).transaction<T>((txn) => action(txn));
    }
    return action(db);
  }
}
