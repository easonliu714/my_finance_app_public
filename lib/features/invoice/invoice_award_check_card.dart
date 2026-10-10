import 'package:flutter/material.dart';

import 'invoice_award_check_presentation.dart';

/// Read-only Issue #13 result surface.
///
/// The card deliberately exposes no redemption, remittance, refresh, or
/// accounting-write action. Those capabilities remain outside the award match
/// projection and require their own explicit authority.
class InvoiceAwardCheckCard extends StatelessWidget {
  const InvoiceAwardCheckCard({
    super.key,
    required this.presentation,
  });

  final InvoiceAwardCheckPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = presentation.warnings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('統一發票中獎檢查', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('期別：${presentation.periodId}'),
            Text('獎別：${presentation.tierLabel}'),
            Text('獎金（稅前）：NT\$ ${presentation.grossAmount}'),
            Text(
              '領獎期間：${_date(presentation.redemptionStart)} ～ '
              '${_date(presentation.redemptionEnd)}',
            ),
            if (presentation.reviewRequired) ...[
              const SizedBox(height: 8),
              const Text('此結果仍有資格或來源資訊需要人工確認。'),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final warning in warnings) Text('• $warning'),
            ],
            const SizedBox(height: 12),
            const Text(InvoiceAwardCheckPresentation.redemptionDisclosure),
            const Text(InvoiceAwardCheckPresentation.remittanceDisclosure),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
