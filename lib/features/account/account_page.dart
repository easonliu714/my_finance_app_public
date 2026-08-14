import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../plan/loan_disbursement_service.dart';
import '../transaction/transaction_providers.dart';
import 'account_detail_page.dart';
import 'account_providers.dart';
import 'debit_card_account_sheet.dart';
import 'account_record.dart';

const List<AccountType> _productionCreatableAccountTypes = <AccountType>[
  AccountType.cash,
  AccountType.bank,
  AccountType.creditCard,
  AccountType.storedValue,
  AccountType.eWallet,
  AccountType.investment,
  AccountType.loan,
  AccountType.other,
];

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  static const routeName = 'accounts';
  static const routePath = '/accounts';

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final Set<AccountType> _collapsedTypes = <AccountType>{};

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('帳戶管理')),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('讀取帳戶失敗：$error')),
        data: (items) {
          final balances = <String, double>{};
          final total = items.fold<double>(0, (sum, account) {
            final detail = ref.watch(accountDetailProvider(account));
            final balance =
                detail.valueOrNull?.currentBalance ?? account.initialBalance;
            balances[account.id] = balance;
            return sum + balance * account.currency.defaultRateToTwd;
          });
          final grouped = _groupAccounts(items);
          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(accountListProvider.notifier).load();
              await ref.read(transactionLedgerProvider.notifier).load();
              for (final account in items) {
                ref.invalidate(accountDetailProvider(account));
              }
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _AccountSummaryCard(total: total, count: items.length),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '帳戶分組',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(_collapsedTypes.clear),
                      child: const Text('全部展開'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('尚未建立帳戶。'),
                    ),
                  )
                else
                  for (final entry in grouped.entries)
                    _AccountTypeSection(
                      type: entry.key,
                      accounts: entry.value,
                      balances: balances,
                      collapsed: _collapsedTypes.contains(entry.key),
                      onToggle: () => setState(() {
                        if (_collapsedTypes.contains(entry.key)) {
                          _collapsedTypes.remove(entry.key);
                        } else {
                          _collapsedTypes.add(entry.key);
                        }
                      }),
                      onOpen: (account) => context.pushNamed(
                        AccountDetailPage.routeName,
                        extra: account,
                      ),
                      onEdit: (account) =>
                           _editAccount(context, ref, account),
                      onArchive: (account) =>
                          _archiveAccount(context, ref, account),
                    ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateAccountSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新增帳戶'),
      ),
    );
  }

  Map<AccountType, List<AccountRecord>> _groupAccounts(
    List<AccountRecord> accounts,
  ) {
    final map = <AccountType, List<AccountRecord>>{};
    for (final account in accounts) {
      map.putIfAbsent(account.type, () => <AccountRecord>[]).add(account);
    }
    return {
      for (final type in AccountType.values)
        if ((map[type] ?? const <AccountRecord>[]).isNotEmpty) type: map[type]!,
    };
  }

  Future<void> _showCreateAccountSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final types = <AccountType>[
      ..._productionCreatableAccountTypes,
      AccountType.debitCard,
    ];
    final selected = await showModalBottomSheet<AccountType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('選擇帳戶類型'),
              subtitle: Text('簽帳金融卡會進入銀行綁定流程。'),
            ),
            for (final type in types)
              ListTile(
                key: Key('create-account-type-${type.name}'),
                leading: Icon(_accountTypeIcon(type)),
                title: Text(type.label),
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    if (selected == AccountType.debitCard) {
      final saved = await showDebitCardAccountSheet(context, ref);
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已新增簽帳金融卡')),
        );
      }
      return;
    }
    await _showAccountSheet(context, ref, initialType: selected);
  }

  Future<void> _editAccount(
    BuildContext context,
    WidgetRef ref,
    AccountRecord account,
  ) async {
    if (account.type == AccountType.debitCard) {
      final saved = await showDebitCardAccountSheet(
        context,
        ref,
        account: account,
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已更新簽帳金融卡')),
        );
      }
      return;
    }
    await _showAccountSheet(context, ref, account: account);
  }

  Future<void> _archiveAccount(
    BuildContext context,
    WidgetRef ref,
    AccountRecord account,
  ) async {
    try {
      await ref.read(accountListProvider.notifier).archive(account.id);
      ref.invalidate(accountDetailProvider(account));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已封存 ${account.displayName}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法封存：$error')),
      );
    }
  }

  Future<void> _showAccountSheet(
    BuildContext context,
    WidgetRef ref, {
    AccountRecord? account,
    AccountType? initialType,
  }) async {
    final isEditing = account != null;
    var sheetAccounts = [
      ...(ref.read(accountListProvider).valueOrNull ??
          const <AccountRecord>[]),
    ];
    List<AccountRecord> disbursementTargets() => sheetAccounts
        .where(
          (item) =>
              !item.isArchived &&
              item.type != AccountType.loan &&
              item.type != AccountType.creditCard &&
              item.type != AccountType.debitCard,
        )
        .toList();
    final nameController = TextEditingController(text: account?.name ?? '');
    final suffixController = TextEditingController(text: account?.suffix ?? '');
    final balanceController = TextEditingController(
      text: account == null ? '0' : _compactNumber(account.initialBalance),
    );
    final creditLimitController = TextEditingController(
      text: account == null ? '0' : _compactNumber(account.creditLimit),
    );
    final statementDayController =
        TextEditingController(text: '${account?.statementDay ?? 15}');
    final paymentDueDayController =
        TextEditingController(text: '${account?.paymentDueDay ?? 5}');
    final reminderDaysController =
        TextEditingController(text: '${account?.reminderDaysBefore ?? 3}');
    final loanPrincipalController = TextEditingController(
      text: account == null ? '0' : _compactNumber(account.loanPrincipal),
    );
    final loanRateController = TextEditingController(
      text: account == null ? '0' : _compactNumber(account.annualInterestRate),
    );
    final loanTermController =
        TextEditingController(text: '${account?.loanTermMonths ?? 0}');
    final loanDueDayController =
        TextEditingController(text: '${account?.loanPaymentDueDay ?? 5}');
    final loanReminderDaysController = TextEditingController(
      text: '${account?.loanReminderDaysBefore ?? 3}',
    );
    final loanHandlingFeeController = TextEditingController(
      text: account == null ? '0' : _compactNumber(account.loanHandlingFee),
    );
    final noteController = TextEditingController(text: account?.note ?? '');
    var type = account?.type ?? initialType ?? AccountType.cash;
    var currency = account?.currency ?? CurrencyCode.twd;
    var paymentReminderEnabled = account?.paymentReminderEnabled ?? false;
    var loanReminderEnabled = account?.loanReminderEnabled ?? false;
    var loanRepaymentMethod = account?.loanRepaymentMethod ??
        LoanRepaymentMethod.equalPrincipalAndInterest;
    var loanStartDate = account?.loanStartDate ?? DateTime.now();
    var loanDisbursementAccountName =
        account?.loanDisbursementAccountName ??
            (disbursementTargets().isEmpty
                ? ''
                : disbursementTargets().first.displayName);
    final selectableTypes = account?.type == AccountType.debitCard
        ? const <AccountType>[AccountType.debitCard]
        : _productionCreatableAccountTypes;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isCreditCard = type == AccountType.creditCard;
          final isLoan = type == AccountType.loan;
          final targets = disbursementTargets();
          final loanPrincipal =
              double.tryParse(loanPrincipalController.text.trim()) ?? 0;
          final loanHandlingFee =
              (double.tryParse(loanHandlingFeeController.text.trim()) ?? 0)
                  .clamp(0, loanPrincipal)
                  .toDouble();
          final loanPreview = AccountRecord(
            id: account?.id ?? 'preview',
            name: 'preview',
            type: AccountType.loan,
            initialBalance: 0,
            sortOrder: 0,
            currency: currency,
            loanPrincipal: loanPrincipal,
            annualInterestRate:
                double.tryParse(loanRateController.text.trim()) ?? 0,
            loanTermMonths: int.tryParse(loanTermController.text.trim()) ?? 0,
            loanRepaymentMethod: loanRepaymentMethod,
            loanStartDate: loanStartDate,
            loanDisbursementAccountName: loanDisbursementAccountName,
            loanHandlingFee: loanHandlingFee,
            loanDisbursementCreated:
                account?.loanDisbursementCreated ?? false,
          );
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isEditing ? '編輯帳戶' : '新增帳戶',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '帳戶名稱'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: suffixController,
                    decoration:
                        const InputDecoration(labelText: '帳戶尾碼 / 帳號末四碼'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AccountType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: '帳戶類型'),
                    items: selectableTypes
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    onChanged: account?.type == AccountType.debitCard
                        ? null
                        : (value) => setModalState(
                              () => type = value ?? AccountType.cash,
                            ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CurrencyCode>(
                    initialValue: currency,
                    decoration: const InputDecoration(labelText: '幣別'),
                    items: CurrencyCode.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.displayLabel),
                          ),
                        )
                        .toList(),
                    onChanged: account?.type == AccountType.debitCard
                        ? null
                        : (value) => setModalState(
                              () => currency = value ?? CurrencyCode.twd,
                            ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: balanceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '初始餘額'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '初始餘額會以帳戶事件記錄；補登更早交易時不回推影響此初始值。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (isCreditCard) ...[
                    const SizedBox(height: 16),
                    Text(
                      '信用卡設定',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    TextField(
                      controller: creditLimitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '信用額度'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: statementDayController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '結帳日',
                              suffixText: '日',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: paymentDueDayController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '繳款日',
                              suffixText: '日',
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('啟用繳款提醒'),
                      value: paymentReminderEnabled,
                      onChanged: (value) => setModalState(
                        () => paymentReminderEnabled = value,
                      ),
                    ),
                    if (paymentReminderEnabled)
                      TextField(
                        controller: reminderDaysController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '提前提醒天數',
                          suffixText: '天',
                        ),
                      ),
                  ],
                  if (isLoan) ...[
                    const SizedBox(height: 16),
                    Text(
                      '借貸設定',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    TextField(
                      controller: loanPrincipalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '本金'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: loanRateController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '年利率',
                              suffixText: '%',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: loanTermController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '期數',
                              suffixText: '月',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<LoanRepaymentMethod>(
                      initialValue: loanRepaymentMethod,
                      decoration: const InputDecoration(labelText: '還款方式'),
                      items: LoanRepaymentMethod.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setModalState(
                        () => loanRepaymentMethod = value ??
                            LoanRepaymentMethod.equalPrincipalAndInterest,
                      ),
                    ),
                    TextField(
                      controller: loanDueDayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '每月還款日',
                        suffixText: '日',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '撥款設定',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('借貸起始 / 撥款日'),
                      subtitle:
                          Text(DateFormat('yyyy/MM/dd').format(loanStartDate)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: loanStartDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setModalState(() => loanStartDate = picked);
                        }
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: targets.any(
                        (item) =>
                            item.displayName == loanDisbursementAccountName,
                      )
                          ? loanDisbursementAccountName
                          : null,
                      decoration: const InputDecoration(labelText: '撥入帳戶'),
                      items: targets
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.displayName,
                              child: Text(item.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: account?.loanDisbursementCreated == true
                          ? null
                          : (value) => setModalState(
                                () => loanDisbursementAccountName = value ?? '',
                              ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: account?.loanDisbursementCreated == true
                            ? null
                            : () async {
                                final created =
                                    await _showQuickCreateDisbursementAccountDialog(
                                  context,
                                  sheetAccounts,
                                  currency,
                                );
                                if (created == null) return;
                                await ref
                                    .read(accountListProvider.notifier)
                                    .updateAccount(created);
                                await ref
                                    .read(accountListProvider.notifier)
                                    .load();
                                if (!context.mounted) return;
                                setModalState(() {
                                  sheetAccounts = [...sheetAccounts, created];
                                  loanDisbursementAccountName =
                                      created.displayName;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '已新增撥入帳戶：${created.displayName}',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('新增撥入帳戶'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: loanHandlingFeeController,
                      enabled: account?.loanDisbursementCreated != true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '手續費',
                        helperText: '保存時會建立手續費支出；已建立撥款事件後不會重複產生。',
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '預估月付 ${_formatMoney(loanPreview.estimatedMonthlyPayment)}，'
                              '首期本金 ${_formatMoney(loanPreview.estimatedFirstMonthPrincipal)}，'
                              '首期利息 ${_formatMoney(loanPreview.estimatedFirstMonthInterest)}',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '撥款入帳 ${_formatMoney(loanPreview.loanPrincipal)} '
                              '${currency.code}，手續費 '
                              '${_formatMoney(loanPreview.loanHandlingFee)}，淨入帳 '
                              '${_formatMoney(loanPreview.loanNetDisbursement)}。',
                            ),
                            if (account?.loanDisbursementCreated == true)
                              const Text('已建立撥款事件；後續編輯不會重複產生撥款交易。'),
                          ],
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('啟用還款提醒'),
                      subtitle: const Text('本階段先保存設定；後續接通知中心與還款入口。'),
                      value: loanReminderEnabled,
                      onChanged: (value) => setModalState(
                        () => loanReminderEnabled = value,
                      ),
                    ),
                    if (loanReminderEnabled)
                      TextField(
                        controller: loanReminderDaysController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '提前提醒天數',
                          suffixText: '天',
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '備註'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) return;
                            final isCredit = type == AccountType.creditCard;
                            final isLoanType = type == AccountType.loan;
                            final base = account ??
                                AccountRecord(
                                  id: const Uuid().v4(),
                                  name: name,
                                  type: type,
                                  initialBalance: 0,
                                  sortOrder: (ref
                                                  .read(accountListProvider)
                                                  .valueOrNull
                                                  ?.length ??
                                              0) *
                                          10 +
                                      100,
                                );
                            var updated = base.copyWith(
                              name: name,
                              type: type,
                              initialBalance: double.tryParse(
                                    balanceController.text.trim(),
                                  ) ??
                                  0,
                              suffix: suffixController.text.trim(),
                              currency: currency,
                              creditLimit: isCredit
                                  ? double.tryParse(
                                        creditLimitController.text.trim(),
                                      ) ??
                                      0.0
                                  : 0.0,
                              statementDay: isCredit
                                  ? _clampDay(
                                      statementDayController.text,
                                      fallback: 15,
                                    )
                                  : 1,
                              paymentDueDay: isCredit
                                  ? _clampDay(
                                      paymentDueDayController.text,
                                      fallback: 5,
                                    )
                                  : 1,
                              paymentReminderEnabled:
                                  isCredit && paymentReminderEnabled,
                              reminderDaysBefore: isCredit
                                  ? _clampInt(
                                      reminderDaysController.text,
                                      fallback: 3,
                                      min: 0,
                                      max: 30,
                                    )
                                  : 3,
                              loanPrincipal: isLoanType
                                  ? double.tryParse(
                                        loanPrincipalController.text.trim(),
                                      ) ??
                                      0.0
                                  : 0.0,
                              annualInterestRate: isLoanType
                                  ? double.tryParse(
                                        loanRateController.text.trim(),
                                      ) ??
                                      0.0
                                  : 0.0,
                              loanTermMonths: isLoanType
                                  ? _clampInt(
                                      loanTermController.text,
                                      fallback: 0,
                                      min: 0,
                                      max: 600,
                                    )
                                  : 0,
                              loanRepaymentMethod: isLoanType
                                  ? loanRepaymentMethod
                                  : LoanRepaymentMethod
                                      .equalPrincipalAndInterest,
                              loanPaymentDueDay: isLoanType
                                  ? _clampDay(
                                      loanDueDayController.text,
                                      fallback: 5,
                                    )
                                  : 1,
                              loanReminderEnabled:
                                  isLoanType && loanReminderEnabled,
                              loanReminderDaysBefore: isLoanType
                                  ? _clampInt(
                                      loanReminderDaysController.text,
                                      fallback: 3,
                                      min: 0,
                                      max: 30,
                                    )
                                  : 3,
                              loanStartDate:
                                  isLoanType ? loanStartDate : null,
                              loanDisbursementAccountName: isLoanType
                                  ? loanDisbursementAccountName
                                  : '',
                              loanHandlingFee: isLoanType
                                  ? (double.tryParse(
                                            loanHandlingFeeController.text
                                                .trim(),
                                          ) ??
                                          0.0)
                                      .clamp(0, double.infinity)
                                      .toDouble()
                                  : 0.0,
                              loanDisbursementCreated: isLoanType &&
                                  base.loanDisbursementCreated,
                              note: noteController.text.trim(),
                            );
                            final shouldCreateDisbursement = isLoanType &&
                                !updated.loanDisbursementCreated;
                            final plan = shouldCreateDisbursement
                                ? buildLoanDisbursementPlan(
                                    loan: updated,
                                    accounts: sheetAccounts,
                                  )
                                : null;
                            if (plan != null) {
                              for (final record in plan.records) {
                                await ref
                                    .read(transactionLedgerProvider.notifier)
                                    .add(record);
                              }
                              updated = updated.copyWith(
                                loanDisbursementCreated: true,
                              );
                            }
                            await ref
                                .read(accountListProvider.notifier)
                                .updateAccount(updated);
                            await ref
                                .read(transactionLedgerProvider.notifier)
                                .load();
                            await ref
                                .read(accountListProvider.notifier)
                                .load();
                            for (final target in sheetAccounts) {
                              ref.invalidate(accountDetailProvider(target));
                            }
                            if (isEditing) {
                              ref.invalidate(accountDetailProvider(account));
                            }
                            ref.invalidate(accountDetailProvider(updated));
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          },
                          child: Text(isEditing ? '更新' : '保存'),
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
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEditing ? '已更新帳戶' : '已新增帳戶')),
      );
    }
  }

  Future<AccountRecord?> _showQuickCreateDisbursementAccountDialog(
    BuildContext context,
    List<AccountRecord> existingAccounts,
    CurrencyCode defaultCurrency,
  ) async {
    final nameController = TextEditingController(text: '銀行帳戶');
    final suffixController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    var type = AccountType.bank;
    var currency = defaultCurrency;
    var errorText = '';
    return showDialog<AccountRecord>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新增撥入帳戶'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '帳戶名稱'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: suffixController,
                  decoration:
                      const InputDecoration(labelText: '帳戶尾碼 / 帳號末四碼'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AccountType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '帳戶類型'),
                  items: const [
                    AccountType.cash,
                    AccountType.bank,
                    AccountType.storedValue,
                    AccountType.eWallet,
                    AccountType.investment,
                    AccountType.other,
                  ]
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => type = value ?? AccountType.bank,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<CurrencyCode>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: '幣別'),
                  items: CurrencyCode.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.displayLabel),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => currency = value ?? CurrencyCode.twd,
                  ),
                ),
                const SizedBox(height: 8),
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
                  setDialogState(() => errorText = '請輸入帳戶名稱');
                  return;
                }
                final duplicate = existingAccounts.any(
                  (account) =>
                      account.name.trim() == name &&
                      account.suffix.trim() == suffix,
                );
                if (duplicate) {
                  setDialogState(
                    () => errorText = '帳戶名稱與尾碼已存在，請調整尾碼 / 帳號末四碼',
                  );
                  return;
                }
                Navigator.of(context).pop(
                  AccountRecord(
                    id: const Uuid().v4(),
                    name: name,
                    suffix: suffix,
                    type: type,
                    initialBalance:
                        double.tryParse(balanceController.text.trim()) ?? 0,
                    sortOrder: existingAccounts.length * 10 + 100,
                    currency: currency,
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
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({required this.total, required this.count});

  final double total;
  final int count;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const CircleAvatar(
                child: Icon(Icons.account_balance_wallet_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('帳戶總覽'),
                    Text('共 $count 個啟用帳戶・以 TWD 換算目前餘額'),
                  ],
                ),
              ),
              Text(
                NumberFormat('#,##0.00').format(total),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
}

class _AccountTypeSection extends StatelessWidget {
  const _AccountTypeSection({
    required this.type,
    required this.accounts,
    required this.balances,
    required this.collapsed,
    required this.onToggle,
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
  });

  final AccountType type;
  final List<AccountRecord> accounts;
  final Map<String, double> balances;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<AccountRecord> onOpen;
  final ValueChanged<AccountRecord> onEdit;
  final ValueChanged<AccountRecord> onArchive;

  @override
  Widget build(BuildContext context) {
    final groupTotalTwd = accounts.fold<double>(
      0,
      (sum, account) =>
          sum +
          (balances[account.id] ?? account.initialBalance) *
              account.currency.defaultRateToTwd,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            onTap: onToggle,
            leading: CircleAvatar(child: Icon(_iconFor(type))),
            title: Text(
              type.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${accounts.length} 個帳戶・TWD 換算淨額 '
              '${NumberFormat('#,##0.##').format(groupTotalTwd)}',
            ),
            trailing: Icon(
              collapsed
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
            ),
          ),
          if (!collapsed) ...[
            const Divider(height: 1),
            for (final account in accounts)
              _AccountTile(
                account: account,
                balance: balances[account.id],
                onOpen: () => onOpen(account),
                onEdit: () => onEdit(account),
                onArchive: () => onArchive(account),
              ),
          ],
        ],
      ),
    );
  }

  IconData _iconFor(AccountType type) => _accountTypeIcon(type);
}

class _AccountTile extends StatefulWidget {
  const _AccountTile({
    required this.account,
    required this.balance,
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
  });

  final AccountRecord account;
  final double? balance;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  State<_AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<_AccountTile> {
  static const double _actionWidth = 88;
  double _dragOffset = 0;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final offset = _revealed ? -_actionWidth : _dragOffset;
    return ClipRect(
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          SizedBox(
            height: 72,
            width: _actionWidth,
            child: TextButton.icon(
              onPressed: () {
                _hide();
                widget.onEdit();
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('編輯'),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(offset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _revealed ? _hide : widget.onOpen,
              onHorizontalDragUpdate: (details) => setState(
                () => _dragOffset =
                    (_dragOffset + details.delta.dx).clamp(-_actionWidth, 0.0),
              ),
              onHorizontalDragEnd: (_) => setState(() {
                _revealed = _dragOffset.abs() > _actionWidth * 0.35;
                _dragOffset = 0;
              }),
              child: ColoredBox(
                color: Theme.of(context).cardColor,
                child: _AccountListTile(
                  account: widget.account,
                  balance: widget.balance,
                  onArchive: widget.onArchive,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _hide() => setState(() {
        _revealed = false;
        _dragOffset = 0;
      });
}

class _AccountListTile extends StatelessWidget {
  const _AccountListTile({
    required this.account,
    required this.balance,
    required this.onArchive,
  });

  final AccountRecord account;
  final double? balance;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final amountLabel = balance == null
        ? '讀取中'
        : '${NumberFormat('#,##0.##').format(balance)} '
            '${account.currency.code}';
    final creditLabel = account.isCreditCard && account.creditLimit > 0
        ? '・額度 ${NumberFormat('#,##0.##').format(account.creditLimit)}'
            '・剩餘 ${NumberFormat('#,##0.##').format(account.creditLimit - (balance ?? 0).abs())}'
        : '';
    final creditDueLabel = account.isCreditCard
        ? '・結帳 ${account.statementDay}日・繳款 ${account.paymentDueDay}日'
            '${account.paymentReminderEnabled ? '・提醒' : ''}'
        : '';
    final loanLabel = account.isLoan
        ? '・本金 ${_formatMoney(account.loanPrincipal)}'
            '・${account.annualInterestRate}%・${account.loanTermMonths}期'
            '・${account.loanRepaymentMethod.label}'
        : '';
    final loanDisbursementLabel =
        account.isLoan && account.loanDisbursementAccountName.isNotEmpty
            ? '・撥入 ${account.loanDisbursementAccountName}'
                '${account.loanDisbursementCreated ? '・已撥款' : '・待撥款'}'
            : '';
    final loanDueLabel = account.isLoan
        ? '・還款 ${account.loanPaymentDueDay}日'
            '${account.loanReminderEnabled ? '・提醒' : ''}'
            '・月付 ${_formatMoney(account.estimatedMonthlyPayment)}'
        : '';
    return ListTile(
      leading: CircleAvatar(child: Icon(_accountTypeIcon(account.type))),
      title: Text(account.displayName),
      subtitle: Text(
        '${account.type.label}・${account.currency.code}'
        '$creditLabel$creditDueLabel$loanLabel'
        '$loanDisbursementLabel$loanDueLabel'
        '${account.note.isEmpty ? '' : '・${account.note}'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            amountLabel,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'archive') onArchive();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'archive', child: Text('封存')),
            ],
          ),
        ],
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
      return Icons.card_membership;
    case AccountType.eWallet:
      return Icons.wallet_outlined;
    case AccountType.investment:
      return Icons.trending_up;
    case AccountType.loan:
      return Icons.request_quote_outlined;
    case AccountType.other:
      return Icons.more_horiz;
  }
}

int _clampDay(String value, {required int fallback}) =>
    _clampInt(value, fallback: fallback, min: 1, max: 31);

int _clampInt(
  String value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = int.tryParse(value.trim()) ?? fallback;
  return parsed.clamp(min, max).toInt();
}

String _compactNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

String _formatMoney(double value) =>
    NumberFormat('#,##0.##').format(value);
