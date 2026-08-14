import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../account/account_providers.dart';
import '../account/account_store.dart';
import 'credit_card_bank_rule_profile.dart';

final creditCardBankRuleProfilesProvider = StateNotifierProvider<CreditCardBankRuleProfilesController, AsyncValue<List<CreditCardBankRuleProfile>>>((ref) {
  final store = ref.watch(accountStoreProvider);
  final controller = CreditCardBankRuleProfilesController(store);
  controller.load();
  return controller;
});

final creditCardBankRuleAssignmentProvider = StateNotifierProvider.autoDispose.family<CreditCardBankRuleAssignmentController, AsyncValue<String?>, String>((ref, cardId) {
  final store = ref.watch(accountStoreProvider);
  final controller = CreditCardBankRuleAssignmentController(store, cardId);
  controller.load();
  return controller;
});

class CreditCardBankRuleProfilesController extends StateNotifier<AsyncValue<List<CreditCardBankRuleProfile>>> {
  CreditCardBankRuleProfilesController(this._store) : super(const AsyncValue.loading());

  final AccountStore _store;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _store.listCreditCardBankRuleProfiles());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> save(CreditCardBankRuleProfile profile) async {
    await _store.upsertCreditCardBankRuleProfile(profile);
    await load();
  }

  Future<CreditCardBankRuleProfile> createFrom(CreditCardBankRuleProfile source, {String? name}) async {
    final profile = source.copyWith(
      id: const Uuid().v4(),
      name: name ?? '${source.name} 副本',
      isVerifiedAgainstStatement: false,
    );
    await save(profile);
    return profile;
  }

  Future<void> delete(String id) async {
    await _store.deleteCreditCardBankRuleProfile(id);
    await load();
  }
}

class CreditCardBankRuleAssignmentController extends StateNotifier<AsyncValue<String?>> {
  CreditCardBankRuleAssignmentController(this._store, this._cardId) : super(const AsyncValue.loading());

  final AccountStore _store;
  final String _cardId;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _store.getCreditCardBankRuleProfileId(_cardId));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> assign(String? profileId) async {
    await _store.setCreditCardBankRuleProfileId(_cardId, profileId);
    await load();
  }
}
