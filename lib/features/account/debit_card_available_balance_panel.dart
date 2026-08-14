import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'debit_card_available_balance_presentation.dart';

class DebitCardAvailableBalancePanel extends StatelessWidget {
  const DebitCardAvailableBalancePanel({
    super.key,
    required this.value,
  });

  final AsyncValue<AccountAvailableBalancePresentation?> value;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const _PanelFrame(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('正在計算簽帳金融卡可用餘額…')),
          ],
        ),
      ),
      error: (error, stackTrace) => _PanelFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '可用餘額暫時無法讀取',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '帳戶明細仍可正常使用；請重新整理後再試。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      data: (presentation) {
        if (presentation == null) return const SizedBox.shrink();
        return _PanelFrame(
          child: _AvailableBalanceContent(presentation: presentation),
        );
      },
    );
  }
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

class _AvailableBalanceContent extends StatelessWidget {
  const _AvailableBalanceContent({required this.presentation});

  final AccountAvailableBalancePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final snapshot = presentation.snapshot;
    final scheme = Theme.of(context).colorScheme;
    final title = presentation.isDebitCardContext
        ? '簽帳金融卡可用餘額'
        : '簽帳金融卡共用資金池';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    presentation.relationshipLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            if (compact) {
              return Column(
                children: [
                  _MetricRow(
                    label: '銀行帳面餘額',
                    value: _money(snapshot.ledgerBalance, snapshot.currency.code),
                  ),
                  const SizedBox(height: 8),
                  _MetricRow(
                    label: '預計扣款保留',
                    value: _money(
                      snapshot.reservedPendingAmount,
                      snapshot.currency.code,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MetricRow(
                    label: '目前可用餘額',
                    value: _money(
                      snapshot.availableBalance,
                      snapshot.currency.code,
                    ),
                    emphasize: true,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: '帳面餘額',
                    value: _money(
                      snapshot.ledgerBalance,
                      snapshot.currency.code,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: '預計扣款',
                    value: _money(
                      snapshot.reservedPendingAmount,
                      snapshot.currency.code,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: '可用餘額',
                    value: _money(
                      snapshot.availableBalance,
                      snapshot.currency.code,
                    ),
                    emphasize: true,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: const Icon(Icons.schedule_outlined, size: 18),
              label: Text('待扣款 ${snapshot.activeReservationCount} 筆'),
              visualDensity: VisualDensity.compact,
            ),
            if (presentation.isLinkedBankContext)
              Chip(
                avatar: const Icon(Icons.credit_card_outlined, size: 18),
                label: Text(
                  '連結 ${presentation.linkedDebitCardAccounts.length} 張卡',
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (snapshot.isOverReserved) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '預計扣款已超過帳面餘額 '
                    '${_money(snapshot.overReservedAmount, snapshot.currency.code)}。'
                    '請先補足資金或確認待扣款狀態。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '此區為 App 內本機帳務估算，依帳面餘額與待扣款紀錄計算，'
          '不代表銀行已完成實際扣款。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: emphasize ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: emphasize ? scheme.onPrimaryContainer : null,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasize ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: emphasize ? scheme.onPrimaryContainer : null,
                ),
          ),
        ],
      ),
    );
  }
}

String _money(double value, String currencyCode) {
  return '${NumberFormat('#,##0.##').format(value)} $currencyCode';
}
