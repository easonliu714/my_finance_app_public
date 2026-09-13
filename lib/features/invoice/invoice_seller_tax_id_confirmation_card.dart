import 'package:flutter/material.dart';

import 'invoice_seller_tax_id_confirmation.dart';

/// P4.20.4+461 explicit sellerTaxId confirmation control.
///
/// This widget never performs Registry lookup and never derives authority from a
/// Registry hit. It only exposes the user's explicit confirmation of the exact
/// current sellerTaxId/source pair to the parent review flow.
class InvoiceSellerTaxIdConfirmationCard extends StatelessWidget {
  const InvoiceSellerTaxIdConfirmationCard({
    super.key,
    required this.state,
    required this.onConfirm,
    this.trustedQrAuthority = false,
    this.busy = false,
  });

  static const Key statusKey = Key('invoice_seller_tax_id_confirmation_status');
  static const Key confirmKey = Key('invoice_seller_tax_id_confirmation_confirm');

  final InvoiceSellerTaxIdConfirmationState state;
  final ValueChanged<InvoiceSellerTaxIdConfirmationState> onConfirm;
  final bool trustedQrAuthority;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final sellerTaxId = state.normalizedSellerTaxId;
    final explicitlyConfirmed = state.explicitlyConfirmedForCurrentValue;
    final authoritative = state.isAuthoritative(
      trustedQrAuthority: trustedQrAuthority,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '賣方統編確認',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text('辨識值：${sellerTaxId.isEmpty ? '—' : sellerTaxId}'),
            const SizedBox(height: 2),
            Text(
              explicitlyConfirmed
                  ? '已確認賣方統編：$sellerTaxId'
                  : trustedQrAuthority
                      ? '已確認賣方統編：$sellerTaxId（QR 權威）'
                      : '已確認賣方統編：尚未確認',
              key: statusKey,
              style: TextStyle(
                fontWeight: authoritative ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              authoritative
                  ? '目前統編具獨立 authority；後續僅可查詢已安裝的本機 Registry。'
                  : state.canExplicitlyConfirm
                      ? 'Registry 不會反向升格此辨識值；請先明確確認目前統編。'
                      : '目前統編不是可確認的有效 8 碼統編，Registry lookup 保持停用。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!trustedQrAuthority && !explicitlyConfirmed) ...<Widget>[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: confirmKey,
                onPressed: busy || !state.canExplicitlyConfirm
                    ? null
                    : () => onConfirm(state.confirmCurrent()),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: const Text('確認此賣方統編'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
