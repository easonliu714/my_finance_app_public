import 'package:flutter/material.dart';

import 'invoice_award_formal_income_posting_service.dart';
import 'invoice_award_payout_bookkeeping_contract.dart';
import 'invoice_award_remittance_receipt_evidence.dart';

/// Production UI authorization boundary, shared with the isolated V24 widget
/// regression. This never posts automatically and cannot bypass Owner option C.
class InvoiceAwardFormalPostingConfirmation {
  const InvoiceAwardFormalPostingConfirmation({
    this.postingService = const InvoiceAwardFormalIncomePostingService(),
  });

  final InvoiceAwardFormalIncomePostingService postingService;

  /// null = canceled/unmounted; true = committed; false = already POSTED.
  /// Revalidate live UI authority after the modal closes, not only when it
  /// opens. No account/SQLite access occurs before explicit confirmation.
  Future<bool?> requestAndPost({
    required BuildContext context,
    required InvoiceAwardPayoutBookkeepingProposal proposal,
    required InvoiceAwardRemittanceReceiptEvidence receipt,
    required DateTime Function() nowUtc,
    required bool Function() authorizationStillValid,
    void Function()? onPostingStarted,
  }) async {
    if (proposal.isDeferredCloud500Prize) {
      throw StateError('CLOUD500_PRODUCTION_DEFERRED_OWNER_OPTION_C');
    }
    if (!receipt.matches(proposal)) {
      throw StateError('INVOICE_AWARD_POSTING_EVIDENCE_INVALID');
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認新增正式發票兌獎收入'),
        content: Text(
          '你已確認指定銀行帳戶實際收到 NT\$${proposal.grossAmount}。'
          '按下新增後，將在日常帳本建立正式收入並影響該帳戶餘額。'
          '這是新的、明確的記帳授權；歷史版本的收款測試紀錄'
          '不會自動補登。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認新增正式收入'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return null;
    if (!authorizationStillValid() || !receipt.matches(proposal)) {
      throw StateError('INVOICE_AWARD_POSTING_UI_AUTHORITY_STALE');
    }
    final authorizedAtUtc = nowUtc();
    if (!authorizedAtUtc.isUtc) {
      throw StateError('INVOICE_AWARD_POSTING_AUTHORIZATION_CLOCK_INVALID');
    }
    // Lock production posting controls before asynchronous ledger access.
    onPostingStarted?.call();
    return postingService.post(
      proposal: proposal,
      receipt: receipt,
      authorizedAtUtc: authorizedAtUtc,
    );
  }
}
