import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../account/account_providers.dart';
import '../account/account_record.dart';
import '../account/account_repository.dart';
import '../account/account_store.dart';
import '../merchant/merchant_record.dart';
import '../merchant/canonical_merchant_repository.dart';
import '../merchant/merchant_store.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import '../transaction/auto_top_up_transaction_store.dart';
import '../transaction/transaction_store.dart';
import 'manual_invoice_draft.dart';
import 'manual_invoice_draft_repository.dart';
import 'manual_invoice_service.dart';

const List<String> _defaultManualInvoiceMerchants = <String>[
  '小七',
  'OK便利商店',
  '7-ELEVEN',
  '全家便利商店',
  '麥當勞',
  '八方雲集',
];

const List<AccountType> _invoicePaymentAccountTypes = <AccountType>[
  AccountType.cash,
  AccountType.bank,
  AccountType.creditCard,
  AccountType.storedValue,
  AccountType.eWallet,
  AccountType.investment,
  AccountType.other,
];

class ManualInvoiceEntryPage extends ConsumerStatefulWidget {
  const ManualInvoiceEntryPage({
    super.key,
    this.service = const ManualInvoiceService(),
    this.repository,
    this.transactionStore,
    this.accountStore,
    this.merchantStore,
    this.merchantOptions,
    this.initialInvoiceDate,
  });

  static const routeName = 'manual-invoice-entry';
  static const routePath = '/invoice/manual/new';

  static const invoiceNumberFieldKey = Key('manual_invoice_number_field');
  static const invoiceDateTileKey = Key('manual_invoice_date_tile');
  static const invoiceTimeTileKey = Key('manual_invoice_time_tile');
  static const sellerNameFieldKey = Key('manual_invoice_seller_field');
  static const addMerchantButtonKey = Key('manual_invoice_add_merchant_button');
  static const addMerchantNameFieldKey = Key('manual_invoice_add_merchant_name_field');
  static const addMerchantAliasFieldKey = Key('manual_invoice_add_merchant_alias_field');
  static const confirmAddMerchantButtonKey = Key('manual_invoice_confirm_add_merchant_button');
  static const totalAmountFieldKey = Key('manual_invoice_total_amount_field');
  static const taxAmountFieldKey = Key('manual_invoice_tax_amount_field');
  static const paymentAccountFieldKey = Key('manual_invoice_payment_account_field');
  static const addAccountButtonKey = Key('manual_invoice_add_account_button');
  static const addAccountNameFieldKey = Key('manual_invoice_add_account_name_field');
  static const addAccountSuffixFieldKey = Key('manual_invoice_add_account_suffix_field');
  static const addAccountInitialBalanceFieldKey = Key('manual_invoice_add_account_initial_balance_field');
  static const addAccountTypeFieldKey = Key('manual_invoice_add_account_type_field');
  static const confirmAddAccountButtonKey = Key('manual_invoice_confirm_add_account_button');
  static const noteFieldKey = Key('manual_invoice_note_field');
  static const saveDraftButtonKey = Key('manual_invoice_save_draft_button');
  static const reviewButtonKey = Key('manual_invoice_review_button');

  final ManualInvoiceService service;
  final ManualInvoiceDraftRepository? repository;
  final TransactionStore? transactionStore;
  final AccountStore? accountStore;
  final MerchantStore? merchantStore;
  final List<String>? merchantOptions;
  final DateTime? initialInvoiceDate;

  @override
  ConsumerState<ManualInvoiceEntryPage> createState() => _ManualInvoiceEntryPageState();
}

class _ManualInvoiceEntryPageState extends ConsumerState<ManualInvoiceEntryPage> {
  late DateTime _invoiceDate;
  late final ManualInvoiceDraftRepository _repository;
  late final TransactionStore _transactionStore;
  late final AccountStore _accountStore;
  late final MerchantStore _merchantStore;
  late Future<List<AccountRecord>> _paymentAccountsFuture;
  late List<String> _merchantOptions;
  final _invoiceNumberController = TextEditingController();
  final _totalAmountController = TextEditingController();
  final _taxAmountController = TextEditingController();
  final _noteController = TextEditingController();
  List<String> _errors = const <String>[];
  List<String> _warnings = const <String>[];
  List<AccountRecord> _paymentAccounts = const <AccountRecord>[];
  AccountRecord? _selectedPaymentAccount;
  String? _selectedMerchant;
  String _paymentAccountLoadError = '';

  bool get _usesInjectedMerchantOptions => widget.merchantOptions != null;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? InMemoryManualInvoiceDraftRepository();
    _transactionStore = widget.transactionStore ?? AutoTopUpTransactionStore.instance;
    _accountStore = widget.accountStore ?? AccountRepository.instance;
    _merchantStore = widget.merchantStore ?? CanonicalMerchantRepository.instance;
    _merchantOptions = _normalizeMerchantOptions(widget.merchantOptions ?? _defaultManualInvoiceMerchants);
    if (!_usesInjectedMerchantOptions) Future<void>.microtask(() => _loadPersistentMerchants());
    final initial = widget.initialInvoiceDate ?? DateTime.now();
    _invoiceDate = DateTime(initial.year, initial.month, initial.day, initial.hour, initial.minute);
    _paymentAccountsFuture = _loadPaymentAccounts();
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _totalAmountController.dispose();
    _taxAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手動輸入發票')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('發票資料', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('此流程只建立本機發票草稿與交易候選，不串接財政部 API、不登入載具，也不會靜默建立正式交易。'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ManualInvoiceEntryPage.invoiceNumberFieldKey,
            controller: _invoiceNumberController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '發票號碼',
              hintText: '例如 AB12345678',
              helperText: '正式交易需為 AB12345678 格式；格式不符可先存草稿，不能建立交易。',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateTimeFieldButton(
                  key: ManualInvoiceEntryPage.invoiceDateTileKey,
                  label: '發票日期',
                  value: _formatDate(_invoiceDate),
                  icon: Icons.calendar_month_outlined,
                  onPressed: _pickInvoiceDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTimeFieldButton(
                  key: ManualInvoiceEntryPage.invoiceTimeTileKey,
                  label: '發票時間',
                  value: _formatTime(_invoiceDate),
                  icon: Icons.schedule_outlined,
                  onPressed: _pickInvoiceTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMerchantPicker(),
          const SizedBox(height: 12),
          TextField(
            key: ManualInvoiceEntryPage.totalAmountFieldKey,
            controller: _totalAmountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '總額', prefixText: 'NT\$ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ManualInvoiceEntryPage.taxAmountFieldKey,
            controller: _taxAmountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '稅額（選填）', prefixText: 'NT\$ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          _buildPaymentAccountPicker(),
          const SizedBox(height: 12),
          TextField(
            key: ManualInvoiceEntryPage.noteFieldKey,
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '備註（選填）', border: OutlineInputBorder()),
          ),
          if (_errors.isNotEmpty || _warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ValidationSummary(errors: _errors, warnings: _warnings),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: ManualInvoiceEntryPage.saveDraftButtonKey,
            onPressed: _saveDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('儲存本機草稿'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: ManualInvoiceEntryPage.reviewButtonKey,
            onPressed: _reviewInvoice,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('檢查並預覽交易候選'),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ManualInvoiceEntryPage.sellerNameFieldKey,
          initialValue: _selectedMerchant,
          decoration: const InputDecoration(
            labelText: '店家名稱',
            hintText: '選擇既有商家',
            border: OutlineInputBorder(),
          ),
          isExpanded: true,
          items: _merchantOptions
              .map(
                (merchant) => DropdownMenuItem<String>(
                  value: merchant,
                  child: Text(merchant, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (merchant) => setState(() => _selectedMerchant = merchant),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ManualInvoiceEntryPage.addMerchantButtonKey,
            onPressed: _showAddMerchantSheet,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('找不到店家？新增商家'),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentAccountPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<AccountRecord>>(
          future: _paymentAccountsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const InputDecorator(
                key: ManualInvoiceEntryPage.paymentAccountFieldKey,
                decoration: InputDecoration(labelText: '付款帳戶', border: OutlineInputBorder()),
                child: Row(
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Expanded(child: Text('正在載入帳戶…')),
                  ],
                ),
              );
            }

            if (_paymentAccounts.isEmpty) {
              return DropdownButtonFormField<AccountRecord>(
                key: ManualInvoiceEntryPage.paymentAccountFieldKey,
                decoration: InputDecoration(
                  labelText: '付款帳戶',
                  helperText: _paymentAccountLoadError.isEmpty ? '請先到「帳戶」新增付款帳戶。' : _paymentAccountLoadError,
                  border: const OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<AccountRecord>>[],
                onChanged: null,
              );
            }

            final selected = _effectiveSelectedPaymentAccount();
            return DropdownButtonFormField<AccountRecord>(
              key: ManualInvoiceEntryPage.paymentAccountFieldKey,
              initialValue: selected,
              decoration: const InputDecoration(labelText: '付款帳戶', border: OutlineInputBorder()),
              isExpanded: true,
              items: _paymentAccounts
                  .map(
                    (account) => DropdownMenuItem<AccountRecord>(
                      value: account,
                      child: Text(account.displayName, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (account) => setState(() => _selectedPaymentAccount = account),
            );
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ManualInvoiceEntryPage.addAccountButtonKey,
            onPressed: _showAddAccountSheet,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('找不到帳戶？新增帳戶'),
          ),
        ),
      ],
    );
  }

  Future<void> _loadPersistentMerchants({String? preferredMerchant}) async {
    try {
      final merchants = await _merchantStore.listMerchants();
      final merged = _normalizeMerchantOptions([
        ..._defaultManualInvoiceMerchants,
        ...merchants.map((merchant) => merchant.displayName),
      ]);
      if (!mounted) return;
      setState(() {
        _merchantOptions = merged;
        if (preferredMerchant != null) {
          _selectedMerchant = preferredMerchant;
        } else if (_selectedMerchant != null && !merged.contains(_selectedMerchant)) {
          _selectedMerchant = null;
        }
      });
    } catch (_) {
      // Keep seeded in-memory options available if local merchant storage is not ready.
    }
  }

  Future<List<AccountRecord>> _loadPaymentAccounts({String? preferredAccountId}) async {
    try {
      final accounts = await _accountStore.listAccounts();
      final paymentAccounts = accounts.where(_isPaymentAccount).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _paymentAccounts = paymentAccounts;
      _selectedPaymentAccount = _preferredPaymentAccount(paymentAccounts, _selectedPaymentAccount, preferredAccountId: preferredAccountId);
      _paymentAccountLoadError = '';
      return paymentAccounts;
    } catch (_) {
      _paymentAccounts = const <AccountRecord>[];
      _selectedPaymentAccount = null;
      _paymentAccountLoadError = '帳戶載入失敗，請返回後再試。';
      return const <AccountRecord>[];
    }
  }

  bool _isPaymentAccount(AccountRecord account) =>
      !account.isArchived &&
      account.type != AccountType.loan &&
      account.type != AccountType.debitCard;

  AccountRecord? _effectiveSelectedPaymentAccount() {
    return _selectedPaymentAccount ?? _preferredPaymentAccount(_paymentAccounts, null);
  }

  AccountRecord? _preferredPaymentAccount(List<AccountRecord> accounts, AccountRecord? current, {String? preferredAccountId}) {
    if (accounts.isEmpty) return null;
    if (preferredAccountId != null) {
      for (final account in accounts) {
        if (account.id == preferredAccountId) return account;
      }
    }
    if (current != null) {
      for (final account in accounts) {
        if (account.id == current.id) return account;
      }
    }
    for (final account in accounts) {
      if (account.type == AccountType.cash || account.displayName == '現金') return account;
    }
    return accounts.first;
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    setState(() => _invoiceDate = DateTime(picked.year, picked.month, picked.day, _invoiceDate.hour, _invoiceDate.minute));
  }

  Future<void> _pickInvoiceTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _invoiceDate.hour, minute: _invoiceDate.minute),
    );
    if (picked == null) return;
    setState(() => _invoiceDate = DateTime(_invoiceDate.year, _invoiceDate.month, _invoiceDate.day, picked.hour, picked.minute));
  }

  ManualInvoiceDraft _createDraftFromInput() {
    final totalAmount = double.tryParse(_totalAmountController.text.trim()) ?? 0;
    final taxText = _taxAmountController.text.trim();
    final taxAmount = taxText.isEmpty ? null : double.tryParse(taxText);
    return widget.service.createDraft(
      invoiceNumber: _invoiceNumberController.text,
      invoiceDate: _invoiceDate,
      sellerName: _selectedMerchant ?? '',
      totalAmount: totalAmount,
      taxAmount: taxAmount,
      note: _noteController.text,
    );
  }

  bool _applyValidation(ManualInvoiceDraft draft) {
    final validation = widget.service.validate(draft);
    final errors = <String>[...validation.errors];
    if (_selectedMerchant == null || _selectedMerchant!.trim().isEmpty) errors.add('請選擇店家');
    if (_effectiveSelectedPaymentAccount() == null) errors.add('請選擇付款帳戶');
    setState(() {
      _errors = errors;
      _warnings = validation.warnings;
    });
    return errors.isEmpty;
  }

  Future<void> _saveDraft() async {
    final draft = _createDraftFromInput();
    if (!_applyValidation(draft)) return;
    try {
      final saved = await _repository.saveDraft(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已儲存本機發票草稿：${saved.invoiceNumber.trim().toUpperCase()}')));
    } on ManualInvoiceDraftDuplicateError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此發票已存在本機草稿，未覆蓋既有資料')));
    }
  }

  Future<void> _reviewInvoice() async {
    final draft = _createDraftFromInput();
    final validation = widget.service.validateForFormalTransaction(draft);
    final errors = <String>[...validation.errors];
    final paymentAccount = _effectiveSelectedPaymentAccount();
    if (_selectedMerchant == null || _selectedMerchant!.trim().isEmpty) errors.add('請選擇店家');
    if (paymentAccount == null) errors.add('請選擇付款帳戶');
    setState(() {
      _errors = errors;
      _warnings = validation.warnings;
    });
    if (errors.isNotEmpty || paymentAccount == null) return;

    final transactionDraft = widget.service.buildTransactionDraft(draft);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('發票轉交易預覽'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReviewLine(label: '發票號碼', value: draft.invoiceNumber.trim().toUpperCase()),
              _ReviewLine(label: '日期時間', value: _formatDateTime(draft.invoiceDate)),
              _ReviewLine(label: '店家', value: transactionDraft.merchantName),
              _ReviewLine(label: '付款帳戶', value: paymentAccount.displayName),
              _ReviewLine(label: '金額', value: 'NT\$ ${transactionDraft.amount.toStringAsFixed(0)}'),
              if (draft.taxAmount != null) _ReviewLine(label: '稅額', value: 'NT\$ ${draft.taxAmount!.toStringAsFixed(0)}'),
              _ReviewLine(label: '備註', value: transactionDraft.note),
              const SizedBox(height: 12),
              const Text('按下確認後才會正式寫入一筆支出交易；取消或返回修改不會建立交易。'),
              if (validation.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final warning in validation.warnings) Text('提醒：$warning'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('返回修改')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('確認建立正式交易')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final record = widget.service.confirmAsExpenseTransaction(
      invoice: draft,
      accountName: paymentAccount.displayName,
    );
    await _insertFormalTransaction(record);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已建立正式支出交易')));
  }

  Future<void> _insertFormalTransaction(TransactionRecord record) async {
    if (widget.transactionStore != null) {
      await _transactionStore.insert(record);
      return;
    }
    await ref.read(transactionLedgerProvider.notifier).add(record);
  }

  Future<void> _showAddMerchantSheet() async {
    final nameController = TextEditingController();
    final aliasController = TextEditingController();
    var errorText = '';
    var isSaving = false;

    final created = await showModalBottomSheet<MerchantRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) {
          Future<void> submit() async {
            final name = nameController.text.trim();
            final alias = aliasController.text.trim();
            if (name.isEmpty) {
              setModalState(() => errorText = '請輸入商家名稱');
              return;
            }

            final merchant = MerchantRecord(
              id: const Uuid().v4(),
              name: name,
              alias: alias,
            );
            final existingNames = <String>{..._merchantOptions};
            if (!_usesInjectedMerchantOptions) {
              try {
                final current = await _merchantStore.listMerchants(includeArchived: true);
                existingNames.addAll(current.map((item) => item.displayName));
              } catch (_) {
                // Keep duplicate protection best-effort; persistence will surface errors below.
              }
            }
            if (existingNames.contains(merchant.displayName)) {
              setModalState(() => errorText = '商家已存在');
              return;
            }

            FocusScope.of(sheetContext).unfocus();
            if (!_usesInjectedMerchantOptions) {
              setModalState(() {
                errorText = '';
                isSaving = true;
              });
              try {
                await _merchantStore.upsertMerchant(merchant);
              } catch (_) {
                if (!sheetContext.mounted) return;
                setModalState(() {
                  isSaving = false;
                  errorText = '商家建立失敗，請稍後再試';
                });
                return;
              }
            }
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop(merchant);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('新增商家', style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('新增後會保存至本機商家主檔，回到此發票並自動選取新商家；不會由自由文字靜默建立商家。'),
                  const SizedBox(height: 12),
                  TextField(
                    key: ManualInvoiceEntryPage.addMerchantNameFieldKey,
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '商家名稱', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: ManualInvoiceEntryPage.addMerchantAliasFieldKey,
                    controller: aliasController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) async {
                      if (!isSaving) await submit();
                    },
                    decoration: const InputDecoration(labelText: '別名 / 備註（選填）', border: OutlineInputBorder()),
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(errorText, style: TextStyle(color: Theme.of(sheetContext).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: isSaving ? null : () => Navigator.of(sheetContext).pop(), child: const Text('取消'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: ManualInvoiceEntryPage.confirmAddMerchantButtonKey,
                          onPressed: isSaving ? null : submit,
                          child: Text(isSaving ? '建立中…' : '建立並選取'),
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
    nameController.dispose();
    aliasController.dispose();

    if (created == null || !mounted) return;
    if (!_usesInjectedMerchantOptions) {
      await _loadPersistentMerchants(preferredMerchant: created.displayName);
      if (!mounted) return;
      if (!_merchantOptions.contains(created.displayName)) {
        setState(() {
          _merchantOptions = _normalizeMerchantOptions([..._merchantOptions, created.displayName]);
          _selectedMerchant = created.displayName;
        });
      }
    } else {
      setState(() {
        _merchantOptions = _normalizeMerchantOptions([..._merchantOptions, created.displayName]);
        _selectedMerchant = created.displayName;
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已新增並選取商家：${created.displayName}')));
  }

  Future<void> _showAddAccountSheet() async {
    final nameController = TextEditingController();
    final suffixController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    var type = AccountType.cash;
    var currency = CurrencyCode.twd;
    var errorText = '';

    final created = await showModalBottomSheet<AccountRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('新增付款帳戶', style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('新增後會回到此發票並自動選取新帳戶；不會由自由文字靜默建立帳戶。'),
                  const SizedBox(height: 12),
                  TextField(
                    key: ManualInvoiceEntryPage.addAccountNameFieldKey,
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '帳戶名稱', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: ManualInvoiceEntryPage.addAccountSuffixFieldKey,
                    controller: suffixController,
                    decoration: const InputDecoration(labelText: '帳戶尾碼 / 備註（選填）', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AccountType>(
                    key: ManualInvoiceEntryPage.addAccountTypeFieldKey,
                    initialValue: type,
                    decoration: const InputDecoration(labelText: '帳戶類型', border: OutlineInputBorder()),
                    items: _invoicePaymentAccountTypes.map((item) => DropdownMenuItem<AccountType>(value: item, child: Text(item.label))).toList(),
                    onChanged: (value) => setModalState(() => type = value ?? AccountType.cash),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CurrencyCode>(
                    initialValue: currency,
                    decoration: const InputDecoration(labelText: '幣別', border: OutlineInputBorder()),
                    items: CurrencyCode.values.map((item) => DropdownMenuItem<CurrencyCode>(value: item, child: Text(item.displayLabel))).toList(),
                    onChanged: (value) => setModalState(() => currency = value ?? CurrencyCode.twd),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: ManualInvoiceEntryPage.addAccountInitialBalanceFieldKey,
                    controller: balanceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '初始餘額', border: OutlineInputBorder()),
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(errorText, style: TextStyle(color: Theme.of(sheetContext).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text('取消'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: ManualInvoiceEntryPage.confirmAddAccountButtonKey,
                          onPressed: () async {
                            final name = nameController.text.trim();
                            final suffix = suffixController.text.trim();
                            if (name.isEmpty) {
                              setModalState(() => errorText = '請輸入帳戶名稱');
                              return;
                            }
                            final current = await _accountStore.listAccounts(includeArchived: true);
                            final duplicated = current.any((account) => account.name.trim() == name && account.suffix.trim() == suffix);
                            if (duplicated) {
                              setModalState(() => errorText = '帳戶名稱與尾碼已存在');
                              return;
                            }
                            final created = AccountRecord(
                              id: const Uuid().v4(),
                              name: name,
                              suffix: suffix,
                              type: type,
                              initialBalance: double.tryParse(balanceController.text.trim()) ?? 0,
                              sortOrder: current.length * 10 + 100,
                              currency: currency,
                            );
                            await _accountStore.upsertAccount(created);
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop(created);
                          },
                          child: const Text('建立並選取'),
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
    nameController.dispose();
    suffixController.dispose();
    balanceController.dispose();

    if (created == null || !mounted) return;
    if (widget.accountStore == null) {
      await ref.read(accountListProvider.notifier).load();
    }
    if (!mounted) return;
    setState(() => _paymentAccountsFuture = _loadPaymentAccounts(preferredAccountId: created.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已新增並選取付款帳戶：${created.displayName}')));
  }
}

class _DateTimeFieldButton extends StatelessWidget {
  const _DateTimeFieldButton({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, overflow: TextOverflow.ellipsis),
          Text(value, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({required this.errors, required this.warnings});

  final List<String> errors;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: errors.isNotEmpty ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errors.isNotEmpty) ...[
              const Text('請先修正以下欄位', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              for (final error in errors) Text('• $error'),
            ],
            if (warnings.isNotEmpty) ...[
              if (errors.isNotEmpty) const SizedBox(height: 8),
              const Text('提醒', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              for (final warning in warnings) Text('• $warning'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

List<String> _normalizeMerchantOptions(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    result.add(trimmed);
  }
  return result;
}

String _formatDate(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
}

String _formatTime(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String _formatDateTime(DateTime value) => '${_formatDate(value)} ${_formatTime(value)}';
