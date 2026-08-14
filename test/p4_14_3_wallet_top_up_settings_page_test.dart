import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/wallet_top_up_persistence.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation.dart';
import 'package:my_finance_app/features/account/wallet_top_up_settings_page.dart';
import 'package:my_finance_app/features/account/wallet_top_up_ui_gateway.dart';

void main() {
  final now = DateTime.utc(2026, 7, 4, 12);

  testWidgets('creates an enabled profile with stable controls', (tester) async {
    await _prepareTallSurface(tester);
    final gateway = _FakeWalletTopUpUiGateway(
      snapshot: _snapshot(profile: null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WalletTopUpSettingsPage(
          account: _wallet,
          gateway: gateway,
          clock: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('低餘額儲值建議'), findsOneWidget);
    expect(find.byKey(WalletTopUpSettingsPage.enableSwitchKey), findsOneWidget);
    expect(find.byKey(WalletTopUpSettingsPage.fundingAccountKey), findsOneWidget);
    expect(find.textContaining('不會建立正式交易'), findsWidgets);

    await tester.enterText(
      find.byKey(WalletTopUpSettingsPage.thresholdKey),
      '200',
    );
    await tester.enterText(
      find.byKey(WalletTopUpSettingsPage.targetAmountKey),
      '800',
    );
    await tester.tap(find.byKey(WalletTopUpSettingsPage.saveKey));
    await tester.pumpAndSettle();

    expect(gateway.savedProfiles, hasLength(1));
    final saved = gateway.savedProfiles.single;
    expect(saved.targetAccountId, _wallet.id);
    expect(saved.fundingAccountId, _bank.id);
    expect(saved.threshold, 200);
    expect(saved.targetBalance, 800);
    expect(saved.isEnabled, isTrue);
    expect(gateway.snapshot.profile?.id, saved.id);
  });

  testWidgets('evaluate persists suggestion and renders funding shortfall',
      (tester) async {
    await _prepareTallSurface(tester);
    final suggestion = _suggestion(
      id: 'wallet-top-up-test',
      evaluatedAt: now,
      fundingAvailableBalance: 100,
      suggestedAmount: 450,
      fundingSufficient: false,
    );
    final gateway = _FakeWalletTopUpUiGateway(
      snapshot: _snapshot(profile: _profile(now)),
      evaluation: suggestion,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WalletTopUpSettingsPage(
          account: _wallet,
          gateway: gateway,
          clock: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(WalletTopUpSettingsPage.evaluateKey), findsOneWidget);
    await tester.tap(find.byKey(WalletTopUpSettingsPage.evaluateKey));
    await tester.pumpAndSettle();

    expect(gateway.evaluationCalls, 1);
    expect(gateway.snapshot.suggestions, hasLength(1));
    expect(gateway.snapshot.suggestions.single.fundingShortfall, 350);
    expect(find.textContaining('尚差 350 TWD'), findsOneWidget);
    expect(
      find.byKey(const Key('wallet-top-up-suggestion-wallet-top-up-test')),
      findsOneWidget,
    );
  });

  testWidgets('dismisses a pending suggestion explicitly', (tester) async {
    await _prepareTallSurface(tester);
    final stored = StoredWalletTopUpSuggestion.fromDomain(
      profileId: 'profile-1',
      suggestion: _suggestion(id: 'dismiss-me', evaluatedAt: now),
      createdAt: now,
    );
    final gateway = _FakeWalletTopUpUiGateway(
      snapshot: _snapshot(
        profile: _profile(now),
        suggestions: <StoredWalletTopUpSuggestion>[stored],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WalletTopUpSettingsPage(
          account: _wallet,
          gateway: gateway,
          clock: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dismissButton =
        find.byKey(const Key('wallet-top-up-dismiss-dismiss-me'));
    expect(dismissButton, findsOneWidget);
    await tester.tap(dismissButton);
    await tester.pumpAndSettle();

    expect(gateway.dismissCalls, 1);
    expect(
      gateway.snapshot.suggestions.single.status,
      WalletTopUpSuggestionStatus.dismissed,
    );
    expect(find.textContaining('已忽略'), findsWidgets);
  });

  testWidgets('shows actionable empty funding account state', (tester) async {
    await _prepareTallSurface(tester);
    final gateway = _FakeWalletTopUpUiGateway(
      snapshot: const WalletTopUpUiSnapshot(
        targetAccount: _wallet,
        eligibleFundingAccounts: <AccountRecord>[],
        suggestions: <StoredWalletTopUpSuggestion>[],
        audits: <WalletTopUpAuditRecord>[],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WalletTopUpSettingsPage(
          account: _wallet,
          gateway: gateway,
          clock: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('沒有同幣別、未封存'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(WalletTopUpSettingsPage.saveKey),
    );
    expect(button.onPressed, isNull);
  });
}

Future<void> _prepareTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

const _wallet = AccountRecord(
  id: 'wallet-1',
  name: '電子錢包',
  type: AccountType.eWallet,
  initialBalance: 0,
  sortOrder: 10,
);

const _bank = AccountRecord(
  id: 'bank-1',
  name: '資金銀行',
  type: AccountType.bank,
  initialBalance: 1000,
  sortOrder: 20,
);

StoredWalletTopUpProfile _profile(DateTime now) => StoredWalletTopUpProfile(
      id: 'profile-1',
      targetAccountId: _wallet.id,
      fundingAccountId: _bank.id,
      currency: CurrencyCode.twd,
      threshold: 100,
      amountMode: WalletTopUpAmountMode.targetBalance,
      targetBalance: 500,
      fixedAmount: 0,
      cooldown: const Duration(hours: 6),
      isEnabled: true,
      createdAt: now,
      updatedAt: now,
    );

WalletTopUpSuggestion _suggestion({
  required String id,
  required DateTime evaluatedAt,
  double fundingAvailableBalance = 1000,
  double suggestedAmount = 450,
  bool fundingSufficient = true,
}) =>
    WalletTopUpSuggestion(
      suggestionId: id,
      targetAccountId: _wallet.id,
      fundingAccountId: _bank.id,
      currency: CurrencyCode.twd,
      amountMode: WalletTopUpAmountMode.targetBalance,
      currentAvailableBalance: 50,
      fundingAvailableBalance: fundingAvailableBalance,
      threshold: 100,
      suggestedAmount: suggestedAmount,
      fundingSufficient: fundingSufficient,
      evaluatedAt: evaluatedAt,
    );

WalletTopUpUiSnapshot _snapshot({
  required StoredWalletTopUpProfile? profile,
  List<StoredWalletTopUpSuggestion> suggestions =
      const <StoredWalletTopUpSuggestion>[],
}) =>
    WalletTopUpUiSnapshot(
      targetAccount: _wallet,
      eligibleFundingAccounts: const <AccountRecord>[_bank],
      profile: profile,
      suggestions: suggestions,
      audits: const <WalletTopUpAuditRecord>[],
    );

class _FakeWalletTopUpUiGateway implements WalletTopUpUiGateway {
  _FakeWalletTopUpUiGateway({
    required this.snapshot,
    this.evaluation,
  });

  WalletTopUpUiSnapshot snapshot;
  WalletTopUpEvaluationResult? evaluation;
  final List<StoredWalletTopUpProfile> savedProfiles = [];
  int evaluationCalls = 0;
  int dismissCalls = 0;

  @override
  Future<WalletTopUpUiSnapshot> load(AccountRecord targetAccount) async =>
      snapshot;

  @override
  Future<StoredWalletTopUpProfile> saveProfile(
    StoredWalletTopUpProfile profile, {
    required DateTime now,
  }) async {
    savedProfiles.add(profile);
    snapshot = WalletTopUpUiSnapshot(
      targetAccount: snapshot.targetAccount,
      eligibleFundingAccounts: snapshot.eligibleFundingAccounts,
      profile: profile,
      suggestions: snapshot.suggestions,
      audits: snapshot.audits,
    );
    return profile;
  }

  @override
  Future<WalletTopUpEvaluationActionResult> evaluateAndPersist({
    required StoredWalletTopUpProfile profile,
    required DateTime evaluatedAt,
  }) async {
    evaluationCalls += 1;
    final result = evaluation ??
        const WalletTopUpNoSuggestion(
          reason: WalletTopUpNoSuggestionReason.balanceAtOrAboveThreshold,
          currentAvailableBalance: 100,
          threshold: 100,
        );
    if (result is! WalletTopUpSuggestion) {
      return WalletTopUpEvaluationActionResult(evaluation: result);
    }
    final stored = StoredWalletTopUpSuggestion.fromDomain(
      profileId: profile.id,
      suggestion: result,
      createdAt: evaluatedAt,
    );
    snapshot = WalletTopUpUiSnapshot(
      targetAccount: snapshot.targetAccount,
      eligibleFundingAccounts: snapshot.eligibleFundingAccounts,
      profile: profile,
      suggestions: <StoredWalletTopUpSuggestion>[
        stored,
        ...snapshot.suggestions,
      ],
      audits: snapshot.audits,
    );
    return WalletTopUpEvaluationActionResult(
      evaluation: result,
      persistence: PersistedWalletTopUpSuggestionResult(
        suggestion: stored,
        replayed: false,
        supersededSuggestionIds: const <String>[],
      ),
    );
  }

  @override
  Future<DismissedWalletTopUpSuggestionResult> dismissSuggestion(
    String suggestionId, {
    required DateTime now,
  }) async {
    dismissCalls += 1;
    final current = snapshot.suggestions.firstWhere(
      (item) => item.id == suggestionId,
    );
    final dismissed = current.copyWith(
      status: WalletTopUpSuggestionStatus.dismissed,
      updatedAt: now,
    );
    snapshot = WalletTopUpUiSnapshot(
      targetAccount: snapshot.targetAccount,
      eligibleFundingAccounts: snapshot.eligibleFundingAccounts,
      profile: snapshot.profile,
      suggestions: snapshot.suggestions
          .map((item) => item.id == suggestionId ? dismissed : item)
          .toList(growable: false),
      audits: snapshot.audits,
    );
    return DismissedWalletTopUpSuggestionResult(
      suggestion: dismissed,
      replayed: false,
    );
  }
}
