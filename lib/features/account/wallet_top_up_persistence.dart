import 'dart:convert';

import 'account_record.dart';
import 'wallet_top_up_recommendation.dart';

enum WalletTopUpSuggestionStatus {
  pending,
  dismissed,
  superseded,
}

enum WalletTopUpAuditEventType {
  profileCreated,
  profileUpdated,
  profileEnabled,
  profileDisabled,
  suggestionCreated,
  suggestionDismissed,
  suggestionSuperseded,
}

enum WalletTopUpPersistenceErrorCode {
  profileNotFound,
  suggestionNotFound,
  targetAccountNotFound,
  fundingAccountNotFound,
  profileIdentityMismatch,
  suggestionReplayConflict,
  suggestionProfileMismatch,
  invalidSuggestionTransition,
}

class WalletTopUpPersistenceException implements Exception {
  const WalletTopUpPersistenceException(this.code, this.message);

  final WalletTopUpPersistenceErrorCode code;
  final String message;

  @override
  String toString() => 'WalletTopUpPersistenceException($code): $message';
}

class StoredWalletTopUpProfile {
  const StoredWalletTopUpProfile({
    required this.id,
    required this.targetAccountId,
    required this.fundingAccountId,
    required this.currency,
    required this.threshold,
    required this.amountMode,
    required this.targetBalance,
    required this.fixedAmount,
    required this.cooldown,
    required this.isEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String targetAccountId;
  final String fundingAccountId;
  final CurrencyCode currency;
  final double threshold;
  final WalletTopUpAmountMode amountMode;
  final double targetBalance;
  final double fixedAmount;
  final Duration cooldown;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  WalletTopUpProfile toDomainProfile({
    String? lastSuggestionId,
    DateTime? lastSuggestedAt,
  }) {
    return WalletTopUpProfile(
      targetAccountId: targetAccountId,
      fundingAccountId: fundingAccountId,
      currency: currency,
      threshold: threshold,
      amountMode: amountMode,
      targetBalance: targetBalance,
      fixedAmount: fixedAmount,
      cooldown: cooldown,
      isEnabled: isEnabled,
      lastSuggestionId: lastSuggestionId,
      lastSuggestedAt: lastSuggestedAt,
    );
  }

  StoredWalletTopUpProfile copyWith({
    String? id,
    String? targetAccountId,
    String? fundingAccountId,
    CurrencyCode? currency,
    double? threshold,
    WalletTopUpAmountMode? amountMode,
    double? targetBalance,
    double? fixedAmount,
    Duration? cooldown,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StoredWalletTopUpProfile(
      id: id ?? this.id,
      targetAccountId: targetAccountId ?? this.targetAccountId,
      fundingAccountId: fundingAccountId ?? this.fundingAccountId,
      currency: currency ?? this.currency,
      threshold: threshold ?? this.threshold,
      amountMode: amountMode ?? this.amountMode,
      targetBalance: targetBalance ?? this.targetBalance,
      fixedAmount: fixedAmount ?? this.fixedAmount,
      cooldown: cooldown ?? this.cooldown,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'target_account_id': targetAccountId,
        'funding_account_id': fundingAccountId,
        'currency_code': currency.code,
        'threshold_amount': threshold,
        'amount_mode': amountMode.name,
        'target_balance_amount': targetBalance,
        'fixed_amount': fixedAmount,
        'cooldown_seconds': cooldown.inSeconds,
        'is_enabled': isEnabled ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory StoredWalletTopUpProfile.fromMap(Map<String, Object?> map) {
    return StoredWalletTopUpProfile(
      id: map['id'] as String,
      targetAccountId: map['target_account_id'] as String,
      fundingAccountId: map['funding_account_id'] as String,
      currency: currencyFromCode(map['currency_code'] as String?),
      threshold: (map['threshold_amount'] as num).toDouble(),
      amountMode: WalletTopUpAmountMode.values.byName(
        map['amount_mode'] as String,
      ),
      targetBalance: (map['target_balance_amount'] as num).toDouble(),
      fixedAmount: (map['fixed_amount'] as num).toDouble(),
      cooldown: Duration(
        seconds: (map['cooldown_seconds'] as num).toInt(),
      ),
      isEnabled: (map['is_enabled'] as num).toInt() == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}

class StoredWalletTopUpSuggestion {
  const StoredWalletTopUpSuggestion({
    required this.id,
    required this.profileId,
    required this.targetAccountId,
    required this.fundingAccountId,
    required this.currency,
    required this.amountMode,
    required this.currentAvailableBalance,
    required this.fundingAvailableBalance,
    required this.threshold,
    required this.suggestedAmount,
    required this.fundingShortfall,
    required this.fundingSufficient,
    required this.status,
    required this.evaluatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String profileId;
  final String targetAccountId;
  final String fundingAccountId;
  final CurrencyCode currency;
  final WalletTopUpAmountMode amountMode;
  final double currentAvailableBalance;
  final double fundingAvailableBalance;
  final double threshold;
  final double suggestedAmount;
  final double fundingShortfall;
  final bool fundingSufficient;
  final WalletTopUpSuggestionStatus status;
  final DateTime evaluatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory StoredWalletTopUpSuggestion.fromDomain({
    required String profileId,
    required WalletTopUpSuggestion suggestion,
    required DateTime createdAt,
    WalletTopUpSuggestionStatus status = WalletTopUpSuggestionStatus.pending,
  }) {
    final normalizedCreatedAt = createdAt.toUtc();
    return StoredWalletTopUpSuggestion(
      id: suggestion.suggestionId,
      profileId: profileId,
      targetAccountId: suggestion.targetAccountId,
      fundingAccountId: suggestion.fundingAccountId,
      currency: suggestion.currency,
      amountMode: suggestion.amountMode,
      currentAvailableBalance: suggestion.currentAvailableBalance,
      fundingAvailableBalance: suggestion.fundingAvailableBalance,
      threshold: suggestion.threshold,
      suggestedAmount: suggestion.suggestedAmount,
      fundingShortfall: suggestion.fundingShortfall,
      fundingSufficient: suggestion.fundingSufficient,
      status: status,
      evaluatedAt: suggestion.evaluatedAt.toUtc(),
      createdAt: normalizedCreatedAt,
      updatedAt: normalizedCreatedAt,
    );
  }

  StoredWalletTopUpSuggestion copyWith({
    WalletTopUpSuggestionStatus? status,
    DateTime? updatedAt,
  }) {
    return StoredWalletTopUpSuggestion(
      id: id,
      profileId: profileId,
      targetAccountId: targetAccountId,
      fundingAccountId: fundingAccountId,
      currency: currency,
      amountMode: amountMode,
      currentAvailableBalance: currentAvailableBalance,
      fundingAvailableBalance: fundingAvailableBalance,
      threshold: threshold,
      suggestedAmount: suggestedAmount,
      fundingShortfall: fundingShortfall,
      fundingSufficient: fundingSufficient,
      status: status ?? this.status,
      evaluatedAt: evaluatedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'profile_id': profileId,
        'target_account_id': targetAccountId,
        'funding_account_id': fundingAccountId,
        'currency_code': currency.code,
        'amount_mode': amountMode.name,
        'current_available_balance': currentAvailableBalance,
        'funding_available_balance': fundingAvailableBalance,
        'threshold_amount': threshold,
        'suggested_amount': suggestedAmount,
        'funding_shortfall': fundingShortfall,
        'funding_sufficient': fundingSufficient ? 1 : 0,
        'status': status.name,
        'evaluated_at': evaluatedAt.toUtc().toIso8601String(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory StoredWalletTopUpSuggestion.fromMap(Map<String, Object?> map) {
    return StoredWalletTopUpSuggestion(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      targetAccountId: map['target_account_id'] as String,
      fundingAccountId: map['funding_account_id'] as String,
      currency: currencyFromCode(map['currency_code'] as String?),
      amountMode: WalletTopUpAmountMode.values.byName(
        map['amount_mode'] as String,
      ),
      currentAvailableBalance:
          (map['current_available_balance'] as num).toDouble(),
      fundingAvailableBalance:
          (map['funding_available_balance'] as num).toDouble(),
      threshold: (map['threshold_amount'] as num).toDouble(),
      suggestedAmount: (map['suggested_amount'] as num).toDouble(),
      fundingShortfall: (map['funding_shortfall'] as num).toDouble(),
      fundingSufficient: (map['funding_sufficient'] as num).toInt() == 1,
      status: WalletTopUpSuggestionStatus.values.byName(
        map['status'] as String,
      ),
      evaluatedAt: DateTime.parse(map['evaluated_at'] as String).toUtc(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}

class WalletTopUpAuditRecord {
  const WalletTopUpAuditRecord({
    required this.id,
    required this.eventType,
    required this.profileId,
    required this.detailsJson,
    required this.createdAt,
    this.suggestionId,
  });

  final String id;
  final WalletTopUpAuditEventType eventType;
  final String profileId;
  final String? suggestionId;
  final String detailsJson;
  final DateTime createdAt;

  Map<String, Object?> get details {
    final decoded = jsonDecode(detailsJson);
    return decoded is Map<String, Object?>
        ? decoded
        : Map<String, Object?>.from(decoded as Map);
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'event_type': eventType.name,
        'profile_id': profileId,
        'suggestion_id': suggestionId,
        'details_json': detailsJson,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory WalletTopUpAuditRecord.fromMap(Map<String, Object?> map) {
    return WalletTopUpAuditRecord(
      id: map['id'] as String,
      eventType: WalletTopUpAuditEventType.values.byName(
        map['event_type'] as String,
      ),
      profileId: map['profile_id'] as String,
      suggestionId: map['suggestion_id'] as String?,
      detailsJson: map['details_json'] as String? ?? '{}',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}

class PersistedWalletTopUpSuggestionResult {
  const PersistedWalletTopUpSuggestionResult({
    required this.suggestion,
    required this.replayed,
    required this.supersededSuggestionIds,
  });

  final StoredWalletTopUpSuggestion suggestion;
  final bool replayed;
  final List<String> supersededSuggestionIds;
}

class DismissedWalletTopUpSuggestionResult {
  const DismissedWalletTopUpSuggestionResult({
    required this.suggestion,
    required this.replayed,
  });

  final StoredWalletTopUpSuggestion suggestion;
  final bool replayed;
}
