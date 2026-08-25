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
    expect(entry, contains('id: original?.id ?? _stableSeedRecordId ?? const Uuid().v4()'));
    expect(entry, contains('if (_stableSeedRecordId != null) return false;'));

    expect(frozen, contains('InvoiceTransactionHandoffReviewCard('));
    expect(frozen, contains('stableRecordId: draft.idempotencyKey'));
    expect(frozen, contains('requireExplicitAccountSelection: true'));
    expect(frozen, contains('requireExplicitCategorySelection: true'));
    expect(frozen, contains('requireExplicitMerchantSelection: true'));
    expect(frozen, contains('occurredAt: occurredAt'));
    expect(frozen, contains('辨識商家候選：'));
    expect(frozen, isNot(contains('transactionLedgerProvider.notifier).add(')));
  });

  test('transaction store exposes stable identity lookup before formal insert', () {
    final store = File(
      'lib/features/transaction/transaction_store.dart',
    ).readAsStringSync();
    expect(store, contains('Future<bool> existsById(String id) async'));
    expect(store, contains('record.id == normalized'));
  });
}
