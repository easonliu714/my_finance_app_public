import 'package:flutter/material.dart';

import 'invoice_merchant_decision_composer.dart';

/// P4.20.4 production UI for explicit merchant identity choice during invoice
/// review.
///
/// The card is deliberately presentation-only: rendering never selects a
/// candidate, writes MerchantBrand state, performs Registry lookup, or writes a
/// formal transaction. The parent review flow owns selection and every separate
/// MerchantBrand binding confirmation.
class InvoiceMerchantDecisionComposerCard extends StatelessWidget {
  const InvoiceMerchantDecisionComposerCard({
    super.key,
    required this.state,
    required this.onSelected,
    required this.onConfirmOfficialBinding,
    this.onConfirmRecognitionBinding,
    this.bindingBusy = false,
  });

  static const Key recognitionLaneKey =
      Key('invoice_merchant_decision_recognition_lane');
  static const Key existingMerchantLaneKey =
      Key('invoice_merchant_decision_existing_lane');
  static const Key officialRegistryLaneKey =
      Key('invoice_merchant_decision_official_lane');
  static const Key recognitionBindingConfirmKey =
      Key('invoice_merchant_decision_recognition_binding_confirm');
  static const Key officialBindingConfirmKey =
      Key('invoice_merchant_decision_official_binding_confirm');

  static Key selectKey(InvoiceMerchantDecisionOption option) =>
      Key('invoice_merchant_decision_select_${option.name}');

  final InvoiceMerchantDecisionComposerState state;
  final ValueChanged<InvoiceMerchantDecisionOption> onSelected;
  final ValueChanged<InvoiceMerchantDecisionSelection>?
      onConfirmRecognitionBinding;
  final ValueChanged<InvoiceMerchantDecisionSelection>
      onConfirmOfficialBinding;
  final bool bindingBusy;

  @override
  Widget build(BuildContext context) {
    final selection = state.selection;
    final recognitionSelected =
        selection?.option == InvoiceMerchantDecisionOption.recognition;
    final officialSelected =
        selection?.option == InvoiceMerchantDecisionOption.officialRegistry;

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
              '商家身份決策',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              '此次辨識、既有正式商家與官方登記資料彼此獨立；未明確選擇前不會自動套用或綁定。',
            ),
            const SizedBox(height: 10),
            _lane(
              context,
              state.candidateFor(InvoiceMerchantDecisionOption.recognition),
              recognitionLaneKey,
              actionLabel: '套用此次辨識',
            ),
            const SizedBox(height: 8),
            _lane(
              context,
              state.candidateFor(
                InvoiceMerchantDecisionOption.existingMerchantBrand,
              ),
              existingMerchantLaneKey,
              actionLabel: '套用既有正式商家',
            ),
            const SizedBox(height: 8),
            _lane(
              context,
              state.candidateFor(InvoiceMerchantDecisionOption.officialRegistry),
              officialRegistryLaneKey,
              actionLabel: '選擇官方登記資料',
            ),
            if (recognitionSelected &&
                selection!.requiresMerchantBindingConfirmation &&
                onConfirmRecognitionBinding != null) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                '此次辨識仍只是候選。若要建立／綁定 MerchantBrand，需再次明確確認，而且賣方統編必須已有獨立權威；此動作不會建立正式交易。',
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: recognitionBindingConfirmKey,
                onPressed: bindingBusy
                    ? null
                    : () => onConfirmRecognitionBinding!(selection),
                icon: bindingBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_business_outlined),
                label: const Text('以此次辨識建立／綁定正式商家'),
              ),
            ],
            if (officialSelected &&
                selection!.requiresMerchantBindingConfirmation) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                '官方資料只是一個候選。若要建立／綁定 MerchantBrand，仍需再次明確確認；此動作不會建立正式交易。',
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: officialBindingConfirmKey,
                onPressed: bindingBusy
                    ? null
                    : () => onConfirmOfficialBinding(selection),
                icon: bindingBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: const Text('依官方資料建立／綁定'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lane(
    BuildContext context,
    InvoiceMerchantDecisionCandidate candidate,
    Key laneKey, {
    required String actionLabel,
  }) {
    final selected = state.selectedOption == candidate.option;
    final displayName = candidate.displayName.trim();
    final sellerTaxId = candidate.sellerTaxId.trim();
    final supporting = candidate.supportingLabel.trim();

    return Container(
      key: laneKey,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.45)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  candidate.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_outline, size: 20),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            displayName.isEmpty ? '目前無可用候選' : displayName,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (sellerTaxId.isNotEmpty) Text('賣方統編：$sellerTaxId'),
          if (supporting.isNotEmpty)
            Text(supporting, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton(
            key: selectKey(candidate.option),
            onPressed: candidate.available
                ? () => onSelected(candidate.option)
                : null,
            child: Text(selected ? '已明確選擇' : actionLabel),
          ),
        ],
      ),
    );
  }
}
