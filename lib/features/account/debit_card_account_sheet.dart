import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'account_providers.dart';
import 'account_record.dart';
import 'debit_card_account_profile.dart';

Future<bool?> showDebitCardAccountSheet(
  BuildContext context,
  WidgetRef ref, {
  AccountRecord? account,
}) async {
  final store = ref.read(accountStoreProvider);
  final debitCardStore = ref.read(debitCardAccountStoreProvider);
  final existingProfile = account == null
      ? null
      : await debitCardStore.getDebitCardProfile(account.id);
  final activeAccounts = ref.read(accountListProvider).valueOrNull ??
      await store.listAccounts();
  var bankAccounts = activeAccounts
      .where((item) => !item.isArchived && item.type == AccountType.bank)
      .toList(growable: true);

  final nameController = TextEditingController(text: account?.name ?? '');
  final suffixController = TextEditingController(text: account?.suffix ?? '');
  final settlementDaysController = TextEditingController(
    text: '${existingProfile?.settlementBusinessDays ?? 2}',
  );
  final noteController = TextEditingController(text: account?.note ?? '');
  var linkedBankAccountId = existingProfile?.linkedBankAccountId ??
      (bankAccounts.isEmpty ? '' : bankAccounts.first.id);
  var profileEnabled = existingProfile?.isEnabled ?? true;
  var errorText = '';
  var saving = false;

  AccountRecord? selectedBank() {
    for (final bank in bankAccounts) {
      if (bank.id == linkedBankAccountId) return bank;
    }
    return null;
  }

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        final bank = selectedBank();
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account == null ? '新增簽帳金融卡' : '編輯簽帳金融卡',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  '簽帳金融卡是獨立清算帳戶；消費會先保留綁定銀行的可用餘額，實際扣款於後續確認。',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('debit-card-name'),
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '卡片名稱'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('debit-card-suffix'),
                  controller: suffixController,
                  decoration: const InputDecoration(
                    labelText: '卡號末四碼',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                Text(
                  '綁定銀行帳戶',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (bankAccounts.isEmpty)
                  Card(
                    key: const Key('debit-card-empty-bank-state'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('目前沒有可綁定的銀行帳戶。'),
                          const SizedBox(height: 4),
                          const Text('請先新增銀行帳戶；卡片幣別會自動跟隨銀行帳戶。'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('debit-card-create-bank'),
                            onPressed: () async {
                              final created = await _showQuickCreateBankDialog(
                                context,
                                activeAccounts,
                              );
                              if (created == null) return;
                              try {
                                await ref
                                    .read(accountListProvider.notifier)
                                    .updateAccount(created);
                                if (!context.mounted) return;
                                setModalState(() {
                                  bankAccounts = [...bankAccounts, created];
                                  linkedBankAccountId = created.id;
                                  errorText = '';
                                });
                              } catch (error) {
                                if (!context.mounted) return;
                                setModalState(() => errorText = '$error');
                              }
                            },
                            icon: const Icon(Icons.account_balance_outlined),
                            label: const Text('新增銀行帳戶'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: const Key('debit-card-linked-bank'),
                    initialValue: bank == null ? null : linkedBankAccountId,
                    decoration: const InputDecoration(
                      labelText: '扣款銀行帳戶',
                    ),
                    items: bankAccounts
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item.id,
                            child: Text(
                              '${item.displayName}・${item.currency.code}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: saving
                        ? null
                        : (value) => setModalState(() {
                              linkedBankAccountId = value ?? '';
                              errorText = '';
                            }),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: '卡片幣別'),
                    child: Text(
                      bank?.currency.displayLabel ?? '請選擇銀行帳戶',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const InputDecorator(
                  decoration: InputDecoration(labelText: '初始餘額'),
                  child: Text('0（清算帳戶固定值）'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('debit-card-settlement-days'),
                  controller: settlementDaysController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '預計扣款工作天',
                    helperText: '預設 T+2；週末、國定假日與補假不計入。',
                    suffixText: '天',
                  ),
                ),
                SwitchListTile(
                  key: const Key('debit-card-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('啟用簽帳金融卡'),
                  subtitle: const Text('停用後不可建立新的消費授權。'),
                  value: profileEnabled,
                  onChanged: saving
                      ? null
                      : (value) => setModalState(
                            () => profileEnabled = value,
                          ),
                ),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: '備註'),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText,
                    key: const Key('debit-card-save-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('debit-card-save'),
                        onPressed: saving || bankAccounts.isEmpty
                            ? null
                            : () async {
                                final name = nameController.text.trim();
                                final linkedBank = selectedBank();
                                final settlementDays = int.tryParse(
                                  settlementDaysController.text.trim(),
                                );
                                if (name.isEmpty) {
                                  setModalState(
                                    () => errorText = '請輸入卡片名稱。',
                                  );
                                  return;
                                }
                                if (linkedBank == null) {
                                  setModalState(
                                    () => errorText = '請選擇扣款銀行帳戶。',
                                  );
                                  return;
                                }
                                if (settlementDays == null ||
                                    settlementDays < 0 ||
                                    settlementDays > 30) {
                                  setModalState(
                                    () => errorText = '預計扣款工作天需介於 0 到 30 天。',
                                  );
                                  return;
                                }

                                final base = account ??
                                    AccountRecord(
                                      id: const Uuid().v4(),
                                      name: name,
                                      type: AccountType.debitCard,
                                      initialBalance: 0,
                                      sortOrder: activeAccounts.length * 10 + 100,
                                    );
                                final updated = base.copyWith(
                                  name: name,
                                  type: AccountType.debitCard,
                                  initialBalance: 0,
                                  suffix: suffixController.text.trim(),
                                  currency: linkedBank.currency,
                                  creditLimit: 0,
                                  statementDay: 1,
                                  paymentDueDay: 1,
                                  paymentReminderEnabled: false,
                                  note: noteController.text.trim(),
                                );
                                try {
                                  final profile = DebitCardAccountProfile.link(
                                    debitCardAccountId: updated.id,
                                    linkedBankAccount: linkedBank,
                                    debitCardCurrency: updated.currency,
                                    settlementBusinessDays: settlementDays,
                                    isEnabled: profileEnabled,
                                  );
                                  setModalState(() {
                                    saving = true;
                                    errorText = '';
                                  });
                                  await debitCardStore.upsertDebitCardAccount(
                                    updated,
                                    profile,
                                  );
                                  await ref
                                      .read(accountListProvider.notifier)
                                      .load();
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop(true);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  setModalState(() {
                                    saving = false;
                                    errorText = _friendlyError(error);
                                  });
                                }
                              },
                        child: Text(saving
                            ? '保存中…'
                            : account == null
                                ? '建立'
                                : '更新'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<AccountRecord?> _showQuickCreateBankDialog(
  BuildContext context,
  List<AccountRecord> existingAccounts,
) async {
  final nameController = TextEditingController(text: '銀行帳戶');
  final suffixController = TextEditingController();
  final balanceController = TextEditingController(text: '0');
  var currency = CurrencyCode.twd;
  var errorText = '';

  return showDialog<AccountRecord>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('新增扣款銀行帳戶'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '帳戶名稱'),
              ),
              TextField(
                controller: suffixController,
                decoration: const InputDecoration(labelText: '帳號末四碼'),
              ),
              DropdownButtonFormField<CurrencyCode>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: '幣別'),
                items: CurrencyCode.values
                    .map(
                      (item) => DropdownMenuItem<CurrencyCode>(
                        value: item,
                        child: Text(item.displayLabel),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setDialogState(
                  () => currency = value ?? CurrencyCode.twd,
                ),
              ),
              TextField(
                controller: balanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '初始餘額'),
              ),
              if (errorText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  errorText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final suffix = suffixController.text.trim();
              if (name.isEmpty) {
                setDialogState(() => errorText = '請輸入帳戶名稱。');
                return;
              }
              final duplicated = existingAccounts.any(
                (item) =>
                    item.name.trim() == name && item.suffix.trim() == suffix,
              );
              if (duplicated) {
                setDialogState(() => errorText = '帳戶名稱與尾碼已存在。');
                return;
              }
              Navigator.of(context).pop(
                AccountRecord(
                  id: const Uuid().v4(),
                  name: name,
                  type: AccountType.bank,
                  initialBalance:
                      double.tryParse(balanceController.text.trim()) ?? 0,
                  sortOrder: existingAccounts.length * 10 + 100,
                  suffix: suffix,
                  currency: currency,
                  note: '由簽帳金融卡建立流程新增',
                ),
              );
            },
            child: const Text('新增'),
          ),
        ],
      ),
    ),
  );
}

String _friendlyError(Object error) {
  if (error is DebitCardAccountLinkException) return error.message;
  if (error is StateError) {
    return error.message.toString();
  }
  return error.toString();
}
