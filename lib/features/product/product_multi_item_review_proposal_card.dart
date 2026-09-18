import 'package:flutter/material.dart';

import 'product_multi_item_review_proposal.dart';

/// Presentation-only view of same-request multi-item recognition evidence.
///
/// This widget deliberately accepts an already-produced proposal and exposes
/// no recognition, persistence, merchant-binding, registry, or transaction
/// write callback. Formal accounting remains behind the existing explicit
/// manual-review and Save flow.
class ProductMultiItemReviewProposalCard extends StatelessWidget {
  const ProductMultiItemReviewProposalCard({
    super.key,
    required this.proposal,
  });

  static const Key titleKey = Key('product_multi_item_review_proposal_title');
  static const Key warningKey = Key('product_multi_item_review_proposal_warning');
  static const Key totalKey = Key('product_multi_item_review_proposal_total');

  final ProductMultiItemReviewProposal proposal;

  @override
  Widget build(BuildContext context) {
    final total = proposal.reconciledTotal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '多品項辨識建議',
              key: titleKey,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text('以下內容來自同一次 AI 辨識，只供人工覆核；不會自動建立正式記帳。'),
            const SizedBox(height: 12),
            for (var index = 0; index < proposal.lines.length; index++) ...[
              _ProposalLine(
                index: index,
                line: proposal.lines[index],
              ),
              if (index != proposal.lines.length - 1)
                const Divider(height: 20),
            ],
            if (proposal.hasAmbiguousLines) ...[
              const SizedBox(height: 12),
              const Text(
                '部分品項的數量、單價或小計仍需人工確認。',
                key: warningKey,
              ),
            ],
            if (total != null) ...[
              const SizedBox(height: 12),
              Text(
                '品項小計合計：${_formatAmount(total)}',
                key: totalKey,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProposalLine extends StatelessWidget {
  const _ProposalLine({required this.index, required this.line});

  final int index;
  final ProductReviewLineProposal line;

  @override
  Widget build(BuildContext context) {
    final name = line.name.trim().isEmpty ? '未辨識品項' : line.name.trim();
    return Semantics(
      key: Key('product_multi_item_review_line_$index'),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}. $name',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '數量 ${_formatOptional(line.quantity)} · '
            '單價 ${_formatOptional(line.unitPrice)} · '
            '小計 ${_formatOptional(line.subtotal)}',
          ),
          if (!line.hasCompleteCalculation || !line.subtotalReconciles)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('此品項需要人工確認'),
            ),
        ],
      ),
    );
  }
}

String _formatOptional(double? value) =>
    value == null ? '待確認' : _formatAmount(value);

String _formatAmount(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
