import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice handoff seed stays explicit-save and fail-closed', () {
    final entry = File(
      'lib/features/transaction/transaction_entry_page.dart',
    ).readAsStringSync();
    final frozen = File(
      'lib/features/invoice/invoice_frozen_review_page.dart',
    ).readAsStringSync();
    final adapter = File(
      'lib/features/invoice/invoice_transaction_entry_seed_adapter.dart',
    ).readAsStringSync();

    expect(entry, contains('this.occurredAt'));
    expect(entry, contains('this.stableRecordId'));
    expect(entry, contains('this.requireExplicitAccountSelection = false'));
    expect(entry, contains('this.requireExplicitCategorySelection = false'));
    expect(entry, contains('this.requireExplicitMerchantSelection = false'));
    expect(entry, contains('_selectedTime = seed?.occurredAt ?? DateTime.now()'));
    expect(entry, contains("? '請選擇付款帳戶'"));
    expect(entry, contains("? '請選擇消費類別'"));
    expect(entry, contains("? '請選擇商家'"));
    expect(entry, contains('if (!_validateExplicitSeedSelections()) return;'));
    expect(entry, contains('existsById(stableRecordId)'));
    expect(entry, contains('此發票已建立交易，未重複新增'));
    expect(
      entry,
      contains('id: original?.id ?? _stableSeedRecordId ?? const Uuid().v4()'),
    );
    expect(entry, contains('if (_stableSeedRecordId != null) return false;'));

    // The frozen-review page owns review and navigation only. Seed construction
    // is intentionally delegated so this page never becomes a second formal
    // transaction-write boundary.
    expect(frozen, contains('InvoiceTransactionHandoffReviewCard('));
    expect(
      frozen,
      contains('buildTransactionEntrySeedFromInvoiceDraft(draft)'),
    );
    expect(frozen, isNot(contains('transactionLedgerProvider.notifier).add(')));

    // The adapter owns the governed invoice -> TransactionEntrySeed contract.
    // Keep idempotency and account/category selection fail-closed, while
    // merchant selection follows whether review already established a formal
    // master binding.
    expect(adapter, contains('if (!draft.canOpenTransactionDraft'));
    expect(adapter, contains("throw StateError('INVOICE_HANDOFF_DRAFT_NOT_READY')"));
    expect(adapter, contains('stableRecordId: draft.idempotencyKey'));
    expect(adapter, contains('requireExplicitAccountSelection: true'));
    expect(adapter, contains('requireExplicitCategorySelection: true'));
    expect(
      adapter,
      contains(
        'requireExplicitMerchantSelection: draft.requiresExplicitMerchantSelection',
      ),
    );
    expect(adapter, contains('occurredAt: occurredAt'));
    expect(adapter, contains('辨識商家候選：'));
    expect(adapter, isNot(contains('transactionLedgerProvider.notifier).add(')));
  });

  test('transaction provider exposes stable identity lookup before formal insert', () {
    final providers = File(
      'lib/features/transaction/transaction_providers.dart',
    ).readAsStringSync();
    final store = File(
      'lib/features/transaction/transaction_store.dart',
    ).readAsStringSync();

    expect(
      providers,
      contains('extension TransactionStoreIdentityLookup on TransactionStore'),
    );
    expect(providers, contains('Future<bool> existsById(String id) async'));
    expect(providers, contains('record.id == normalized'));
    expect(store, isNot(contains('Future<bool> existsById(String id)')));
  });
}
