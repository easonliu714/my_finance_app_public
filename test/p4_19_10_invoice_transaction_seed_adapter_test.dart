import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_entry_seed_adapter.dart';
import 'package:my_finance_app/features/invoice/invoice_transaction_handoff_contract.dart';

void main() {
  test('explicitly bound formal merchant is carried without second selection', () {
    final seed = buildTransactionEntrySeedFromInvoiceDraft(
      _draft(formalMerchantName: '測試商店'),
    );

    expect(seed.merchantName, '測試商店');
    expect(seed.requireExplicitMerchantSelection, isFalse);
    expect(seed.note, isNot(contains('尚未升格為正式商家')));
    expect(seed.stableRecordId, 'invoice-review:AB12345678:20260826:12345675');
  });

  test('recognized-only merchant remains a candidate and fails closed', () {
    final seed = buildTransactionEntrySeedFromInvoiceDraft(
      _draft(formalMerchantName: ''),
    );

    expect(seed.merchantName, isNull);
    expect(seed.requireExplicitMerchantSelection, isTrue);
    expect(seed.note, contains('辨識商家候選：OCR 商家（尚未升格為正式商家）'));
  });

  test('adapter rejects a handoff draft that cannot open transaction entry', () {
    final invalid = _draft(
      formalMerchantName: '',
      amount: null,
    );

    expect(
      () => buildTransactionEntrySeedFromInvoiceDraft(invalid),
      throwsA(isA<StateError>()),
    );
  });
}

InvoiceTransactionHandoffDraft _draft({
  required String formalMerchantName,
  double? amount = 120,
}) {
  return InvoiceTransactionHandoffDraft(
    reviewConfirmed: true,
    amount: amount,
    occurredAt: DateTime(2026, 8, 26, 20, 10),
    recognizedMerchantCandidate: 'OCR 商家',
    formalMerchantName: formalMerchantName,
    formalAccountName: '',
    formalCategory: '',
    invoiceNumber: 'AB12345678',
    sellerTaxId: '12345675',
    invoicePeriod: '115年7-8月份',
    randomCode: '2468',
    idempotencyKey: 'invoice-review:AB12345678:20260826:12345675',
    note: '來源：發票辨識人工覆核',
    warnings: <String>[
      if (formalMerchantName.isEmpty) 'FORMAL_MERCHANT_SELECTION_REQUIRED',
      'FORMAL_ACCOUNT_SELECTION_REQUIRED',
      'FORMAL_CATEGORY_SELECTION_REQUIRED',
    ],
  );
}
