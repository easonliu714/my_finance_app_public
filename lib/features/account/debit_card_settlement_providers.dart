import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/production_schema_v19.dart';
import '../transaction/debit_card_settlement_confirmation_service.dart';
import '../transaction/debit_card_settlement_presentation.dart';
import '../transaction/debit_card_settlement_read_service.dart';
import '../transaction/debit_card_settlement_reminder.dart';
import '../transaction/flutter_local_debit_card_settlement_reminder_port.dart';
import '../transaction/transaction_providers.dart';
import 'account_providers.dart';
import 'account_record.dart';
import 'account_repository.dart';

final debitCardSettlementReadServiceProvider =
    Provider<DebitCardSettlementReadService>((ref) {
  return DebitCardSettlementReadService(
    databaseProvider: () => AccountRepository.instance.database,
  );
});

final debitCardSettlementConfirmationServiceProvider =
    Provider<DebitCardSettlementConfirmationService>((ref) {
  return DebitCardSettlementConfirmationService(
    databaseProvider: () async {
      final db = await AccountRepository.instance.database;
      // Keep the confirmation boundary fail-safe on an upgraded V18 database
      // even before the canonical opener migration is exercised by tests.
      await createCanonicalProductionV19Tables(db);
      return db;
    },
  );
});

final debitCardSettlementReminderPortProvider =
    Provider<DebitCardSettlementReminderPort>((ref) {
  if (kIsWeb || !Platform.isAndroid) {
    return const NoopDebitCardSettlementReminderPort();
  }
  return FlutterLocalDebitCardSettlementReminderPort();
});

final debitCardSettlementReminderReconciliationServiceProvider =
    Provider<DebitCardSettlementReminderReconciliationService>((ref) {
  return DebitCardSettlementReminderReconciliationService(
    port: ref.watch(debitCardSettlementReminderPortProvider),
  );
});

final accountDebitCardSettlementPresentationProvider = FutureProvider.autoDispose
    .family<List<DebitCardSettlementPresentation>, AccountRecord>(
  (ref, account) async {
    ref.watch(accountListProvider);
    ref.watch(transactionLedgerProvider);
    final service = ref.watch(debitCardSettlementReadServiceProvider);
    return service.loadForAccount(account, now: DateTime.now().toUtc());
  },
);

final debitCardSettlementReminderReconciliationProvider =
    FutureProvider.autoDispose<int>((ref) async {
  ref.watch(accountListProvider);
  ref.watch(transactionLedgerProvider);
  final readService = ref.watch(debitCardSettlementReadServiceProvider);
  final reconcileService =
      ref.watch(debitCardSettlementReminderReconciliationServiceProvider);
  final now = DateTime.now().toUtc();
  final settlements = await readService.loadAllPending(now: now);
  await reconcileService.reconcile(settlements: settlements, now: now);
  return settlements.length;
});
