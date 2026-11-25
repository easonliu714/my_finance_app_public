import 'dart:async';

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
    required FutureOr<bool> Function() authorizationStillValid,
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
          '你已確認指定銀行帳戶實際收到 NT\$'
            '${receipt.actualReceivedAmount}。'
          '官方獎額為 NT\$'
            '${proposal.grossAmount}。'
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
    // Production authority may require a fresh asynchronous preferences
    // read. Recheck mounted after that await before any formal ledger access.
    final stillAuthorized = await authorizationStillValid();
    if (!context.mounted || !stillAuthorized || !receipt.matches(proposal)) {
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

/// Collect a user-confirmed receipt amount without changing pasted text.
/// Returns null on cancel; does not write receipt evidence or the ledger.
Future<int?> requestInvoiceAwardReceivedAmount({
  required BuildContext context,
  required int grossAmount,
}) {
  var amountText = grossAmount.toString();
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        // Validate the entire input. Never strip characters from a money value.
        final amount = amountText.isEmpty ||
                RegExp(r'[^0-9]').hasMatch(amountText)
            ? null
            : int.tryParse(amountText);
        final valid = amount != null &&
            InvoiceAwardRemittanceReceiptEvidence.isValidReceivedAmount(
                amount, grossAmount);
        return AlertDialog(
          title: const Text('確認銀行已實際收到獎金'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('官方獎額 NT\$${grossAmount}，請確認實際收到的金額。'
                    '本紀錄並非銀行或財政部驗證；此次不會新增交易或修改餘額。'
                    '正式入帳需要再次明確授權。'),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('invoice_award_actual_received_amount'),
                  initialValue: amountText,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '實際收到金額（NT\$）',
                    errorText: valid ? null : '請輸入大於零且不超過官方獎額的整數',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => amountText = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.of(dialogContext).pop(amount)
                  : null,
              child: const Text('已收到，記錄日期'),
            ),
          ],
        );
      },
    ),
  );
}
