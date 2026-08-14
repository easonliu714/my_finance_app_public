import 'package:flutter/material.dart';

import 'invoice_award_governance.dart';

class CloudInvoiceAwardGovernanceCard extends StatelessWidget {
  const CloudInvoiceAwardGovernanceCard({
    super.key,
    this.portalLink = CloudInvoicePortalLink.ministryOfFinance,
    this.candidateCount = 0,
    this.reviewCount = 0,
  });

  static const Key cardKey = Key('cloud_invoice_award_governance_card');
  static const Key portalLinkKey = Key('cloud_invoice_award_portal_link');
  static const Key summaryKey = Key('cloud_invoice_award_summary');

  final CloudInvoicePortalLink portalLink;
  final int candidateCount;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '雲端發票與對獎治理',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const _GovernanceChip(label: 'review-first'),
              ],
            ),
            const SizedBox(height: 8),
            Text(portalLink.title, key: portalLinkKey, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(portalLink.description),
            const SizedBox(height: 8),
            SelectableText(portalLink.officialUrl),
            const SizedBox(height: 12),
            Text(
              '對獎候選：$candidateCount，待審核：$reviewCount',
              key: summaryKey,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(InvoiceAwardGovernanceCopy.noCredentialCustody),
            const SizedBox(height: 4),
            const Text(InvoiceAwardGovernanceCopy.reviewFirst),
          ],
        ),
      ),
    );
  }
}

class _GovernanceChip extends StatelessWidget {
  const _GovernanceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
}
