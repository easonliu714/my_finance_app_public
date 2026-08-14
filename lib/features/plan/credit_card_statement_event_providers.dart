import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_store.dart';
import 'credit_card_statement_event.dart';

final creditCardStatementEventsProvider = StateNotifierProvider.autoDispose.family<CreditCardStatementEventsController, AsyncValue<List<CreditCardStatementEvent>>, String>((ref, cardId) {
  final store = ref.watch(accountStoreProvider);
  final controller = CreditCardStatementEventsController(store, cardId);
  controller.load();
  return controller;
});

class CreditCardStatementEventsController extends StateNotifier<AsyncValue<List<CreditCardStatementEvent>>> {
  CreditCardStatementEventsController(this._store, this._cardId) : super(const AsyncValue.loading());

  final AccountStore _store;
  final String _cardId;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final events = await _store.listCreditCardStatementEvents(_cardId);
      state = AsyncValue.data(events);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> saveSnapshot(CreditCardStatementEvent event) async {
    await _store.upsertCreditCardStatementEvent(event);
    await load();
  }

  Future<void> deleteSnapshot(String id) async {
    await _store.deleteCreditCardStatementEvent(id);
    await load();
  }
}
