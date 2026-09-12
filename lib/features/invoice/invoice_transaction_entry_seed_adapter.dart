import '../transaction/transaction_entry_page.dart';
import 'invoice_transaction_handoff_contract.dart';

/// Converts a reviewed invoice handoff into the existing editable transaction
/// entry boundary. This adapter never persists a transaction; formal creation
/// remains owned by TransactionEntryPage's explicit Save action.
TransactionEntrySeed buildTransactionEntrySeedFromInvoiceDraft(
  InvoiceTransactionHandoffDraft draft,
) {
  final amount = draft.amount;
  final occurredAt = draft.occurredAt;
  if (!draft.canOpenTransactionDraft || amount == null || occurredAt == null) {
    throw StateError('INVOICE_HANDOFF_DRAFT_NOT_READY');
  }

  final formalMerchant = draft.formalMerchantName.trim();
  final recognizedMerchant = draft.recognizedMerchantCandidate.trim();
  final note = <String>[
    draft.note,
    if (formalMerchant.isEmpty && recognizedMerchant.isNotEmpty)
      '辨識商家候選：$recognizedMerchant（尚未升格為正式商家）',
  ].where((value) => value.trim().isNotEmpty).join('\n');

  return TransactionEntrySeed(
    amount: amount,
    occurredAt: occurredAt,
    merchantName: formalMerchant.isEmpty ? null : formalMerchant,
    note: note,
    stableRecordId: draft.idempotencyKey,
    requireExplicitAccountSelection: true,
    requireExplicitCategorySelection: true,
    requireExplicitMerchantSelection: draft.requiresExplicitMerchantSelection,
  );
}
