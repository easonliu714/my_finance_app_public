import 'account_record.dart';
import 'account_repository.dart';
import 'wallet_top_up_persistence.dart';
import 'wallet_top_up_recommendation.dart';
import 'wallet_top_up_recommendation_read_service.dart';
import 'wallet_top_up_recommendation_read_source.dart';
import 'wallet_top_up_repository.dart';

class WalletTopUpUiSnapshot {
  const WalletTopUpUiSnapshot({
    required this.targetAccount,
    required this.eligibleFundingAccounts,
    required this.suggestions,
    required this.audits,
    this.profile,
  });

  final AccountRecord targetAccount;
  final List<AccountRecord> eligibleFundingAccounts;
  final StoredWalletTopUpProfile? profile;
  final List<StoredWalletTopUpSuggestion> suggestions;
  final List<WalletTopUpAuditRecord> audits;

  StoredWalletTopUpSuggestion? get latestSuggestion =>
      suggestions.isEmpty ? null : suggestions.first;
}

class WalletTopUpEvaluationActionResult {
  const WalletTopUpEvaluationActionResult({
    required this.evaluation,
    this.persistence,
  });

  final WalletTopUpEvaluationResult evaluation;
  final PersistedWalletTopUpSuggestionResult? persistence;

  bool get persisted => persistence != null;
}

abstract interface class WalletTopUpUiGateway {
  Future<WalletTopUpUiSnapshot> load(AccountRecord targetAccount);

  Future<StoredWalletTopUpProfile> saveProfile(
    StoredWalletTopUpProfile profile, {
    required DateTime now,
  });

  Future<WalletTopUpEvaluationActionResult> evaluateAndPersist({
    required StoredWalletTopUpProfile profile,
    required DateTime evaluatedAt,
  });

  Future<DismissedWalletTopUpSuggestionResult> dismissSuggestion(
    String suggestionId, {
    required DateTime now,
  });
}

class ProductionWalletTopUpUiGateway implements WalletTopUpUiGateway {
  ProductionWalletTopUpUiGateway._({
    required AccountRepository accountRepository,
    required WalletTopUpRepository walletRepository,
  })  : _accountRepository = accountRepository,
        _walletRepository = walletRepository,
        _readService = WalletTopUpRecommendationReadService(
          source: AccountRepositoryWalletTopUpRecommendationReadSource(
            accountRepository,
          ),
        );

  final AccountRepository _accountRepository;
  final WalletTopUpRepository _walletRepository;
  final WalletTopUpRecommendationReadService _readService;

  static Future<ProductionWalletTopUpUiGateway> create() async {
    final accountRepository = AccountRepository.instance;
    final database = await accountRepository.database;
    return ProductionWalletTopUpUiGateway._(
      accountRepository: accountRepository,
      walletRepository: WalletTopUpRepository(database),
    );
  }

  @override
  Future<WalletTopUpUiSnapshot> load(AccountRecord targetAccount) async {
    final accounts = await _accountRepository.listAccounts(
      includeArchived: true,
    );
    final currentTarget = accounts.firstWhere(
      (item) => item.id == targetAccount.id,
      orElse: () => targetAccount,
    );
    final profile = await _walletRepository.getProfileForTargetAccount(
      currentTarget.id,
    );
    final suggestions = profile == null
        ? const <StoredWalletTopUpSuggestion>[]
        : await _walletRepository.listSuggestions(profileId: profile.id);
    final audits = profile == null
        ? const <WalletTopUpAuditRecord>[]
        : await _walletRepository.listAudits(profileId: profile.id);
    final eligibleFundingAccounts = accounts
        .where(
          (item) =>
              !item.isArchived &&
              item.id != currentTarget.id &&
              item.currency == currentTarget.currency &&
              item.type != AccountType.creditCard &&
              item.type != AccountType.debitCard &&
              item.type != AccountType.loan,
        )
        .toList(growable: false)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return WalletTopUpUiSnapshot(
      targetAccount: currentTarget,
      eligibleFundingAccounts:
          List<AccountRecord>.unmodifiable(eligibleFundingAccounts),
      profile: profile,
      suggestions: List<StoredWalletTopUpSuggestion>.unmodifiable(suggestions),
      audits: List<WalletTopUpAuditRecord>.unmodifiable(audits),
    );
  }

  @override
  Future<StoredWalletTopUpProfile> saveProfile(
    StoredWalletTopUpProfile profile, {
    required DateTime now,
  }) {
    return _walletRepository.upsertProfile(profile, now: now);
  }

  @override
  Future<WalletTopUpEvaluationActionResult> evaluateAndPersist({
    required StoredWalletTopUpProfile profile,
    required DateTime evaluatedAt,
  }) async {
    final suggestions = await _walletRepository.listSuggestions(
      profileId: profile.id,
    );
    final latest = suggestions.isEmpty ? null : suggestions.first;
    final evaluation = await _readService.evaluate(
      profile: profile.toDomainProfile(
        lastSuggestionId: latest?.id,
        lastSuggestedAt: latest?.evaluatedAt,
      ),
      evaluatedAt: evaluatedAt,
    );
    if (evaluation is! WalletTopUpSuggestion) {
      return WalletTopUpEvaluationActionResult(evaluation: evaluation);
    }
    final persistence = await _walletRepository.persistSuggestion(
      profileId: profile.id,
      suggestion: evaluation,
      now: evaluatedAt,
    );
    return WalletTopUpEvaluationActionResult(
      evaluation: evaluation,
      persistence: persistence,
    );
  }

  @override
  Future<DismissedWalletTopUpSuggestionResult> dismissSuggestion(
    String suggestionId, {
    required DateTime now,
  }) {
    return _walletRepository.dismissSuggestion(suggestionId, now: now);
  }
}
