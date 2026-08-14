import 'package:flutter/material.dart';

import '../account/account_record.dart';

Future<AccountRecord?> showGroupedAccountChoiceSheet(
  BuildContext context, {
  required String title,
  required List<AccountRecord> accounts,
  required String selectedDisplayName,
  String? selectedAccountId,
}) {
  final grouped = <AccountType, List<AccountRecord>>{};
  for (final account in accounts.where((item) => !item.isArchived)) {
    grouped.putIfAbsent(account.type, () => <AccountRecord>[]).add(account);
  }
  for (final group in grouped.values) {
    group.sort((left, right) {
      final byOrder = left.sortOrder.compareTo(right.sortOrder);
      if (byOrder != 0) return byOrder;
      return left.displayName.compareTo(right.displayName);
    });
  }

  final activeAccounts = grouped.values.expand((group) => group).toList();
  final matchingDisplayNames = activeAccounts
      .where((account) => account.displayName == selectedDisplayName)
      .toList(growable: false);
  final resolvedSelectedAccountId = selectedAccountId ??
      (matchingDisplayNames.length == 1
          ? matchingDisplayNames.single.id
          : null);

  return showModalBottomSheet<AccountRecord>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final type in AccountType.values)
                    if (grouped[type]?.isNotEmpty ?? false) ...[
                      _AccountTypeHeader(type: type),
                      for (final account in grouped[type]!)
                        ListTile(
                          key: Key(
                            'transaction-account-option-${account.id}',
                          ),
                          leading: Icon(_accountTypeIcon(account.type)),
                          title: Text(account.displayName),
                          subtitle: Text(
                            '${account.type.label}・${account.currency.displayLabel}',
                          ),
                          trailing: account.id == resolvedSelectedAccountId
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(context).pop(account),
                        ),
                      const Divider(height: 12),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AccountTypeHeader extends StatelessWidget {
  const _AccountTypeHeader({required this.type});

  final AccountType type;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        key: Key('transaction-account-group-${type.name}'),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Text(
          type.label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ),
    );
  }
}

IconData _accountTypeIcon(AccountType type) {
  switch (type) {
    case AccountType.cash:
      return Icons.payments_outlined;
    case AccountType.bank:
      return Icons.account_balance_outlined;
    case AccountType.debitCard:
      return Icons.credit_card_outlined;
    case AccountType.creditCard:
      return Icons.credit_card;
    case AccountType.storedValue:
      return Icons.subway_outlined;
    case AccountType.eWallet:
      return Icons.account_balance_wallet_outlined;
    case AccountType.investment:
      return Icons.trending_up;
    case AccountType.loan:
      return Icons.request_quote_outlined;
    case AccountType.other:
      return Icons.more_horiz;
  }
}
