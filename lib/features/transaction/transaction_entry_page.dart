import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../account/account_page.dart';
import '../account/account_providers.dart';
import '../account/account_record.dart';
import '../category/expense_category_repository.dart';
import '../category/expense_category_schema.dart';
import '../invoice/cloud_invoice_supplement_note.dart';
import '../invoice/cloud_invoice_transaction_detail.dart';
import '../merchant/canonical_merchant_repository.dart';
import '../plan/source_transaction_installment_entry_card.dart';
import 'grouped_account_choice_sheet.dart';
import 'transaction_providers.dart';
import 'transaction_record.dart';
import 'transaction_type.dart';

class TransactionEntrySeed {
  const TransactionEntrySeed({
    this.accountName,
    this.fromAccountName,
    this.toAccountName,
    this.amount,
    this.category,
    this.merchantName,
    this.note,
    this.initialType = TransactionType.expense,
  });

  final String? accountName;
  final String? fromAccountName;
  final String? toAccountName;
  final double? amount;
  final String? category;
  final String? merchantName;
  final String? note;
  final TransactionType initialType;
}

class TransactionEntryPage extends ConsumerStatefulWidget {
  const TransactionEntryPage({
    super.key,
    this.initialType = TransactionType.expense,
    this.initialRecord,
    this.seed,
  });

  static const routeName = 'transaction-entry';
  static const routePath = '/transaction/new';

  final TransactionType initialType;
  final TransactionRecord? initialRecord;
  final TransactionEntrySeed? seed;

  @override
  ConsumerState<TransactionEntryPage> createState() => _TransactionEntryPageState();
}

class _TransactionEntryPageState extends ConsumerState<TransactionEntryPage> {
  late TransactionType _selectedType;
  String _amountText = '0.00';
  String _expressionText = '';
  double? _operand;
  String? _operator;
  bool _startNewNumber = true;
  bool _isSaving = false;
  bool _isOpeningInstallment = false;
  String? _seededAccountName;
  String? _seededFromAccountName;
  String? _seededToAccountName;
  TransactionRecord? _savedNewRecord;

  String _selectedCategory = '早餐';
  DateTime _selectedTime = DateTime.now();
  String _selectedAccount = '現金';
  String _selectedFromAccount = '銀行帳戶';
  String _selectedToAccount = '一卡通 Money';
  String _selectedMember = '自己';
  String _selectedMerchant = '不使用商家';
  String _selectedTag = '日常';
  String _note = '';
  CurrencyCode _selectedCurrency = CurrencyCode.twd;
  String _exchangeRateText = '1';

  final List<String> _expenseCategories = <String>[
    ...canonicalDefaultExpenseCategories,
  ];
  final List<String> _incomeCategories = const ['福利補貼', '工資薪水', '獎金薪水', '現金回饋', '退款返款', '發票兌獎', '利息', '全部'];
  final List<String> _transferCategories = const ['轉帳', '投資', '贖回', '存錢', '取錢'];
  final List<String> _loanCategories = const ['借入', '借出', '還款', '收款'];
  final List<String> _members = const ['自己', '家人', '同事'];
  final List<String> _merchants = const ['不使用商家', 'OK便利商店', '7-ELEVEN', '全家便利商店', '麥當勞', '八方雲集'];
  final List<String> _tags = const ['日常', '工作', '家庭', '報銷', '旅遊'];

  bool get _isEditing => widget.initialRecord != null;

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    if (record == null) {
      final seed = widget.seed;
      _selectedType = seed?.initialType ?? widget.initialType;
      _selectedCategory = _categoriesFor(_selectedType).first;
      final seededAccount = seed?.accountName?.trim();
      final seededFromAccount = seed?.fromAccountName?.trim();
      final seededToAccount = seed?.toAccountName?.trim();
      final seededCategory = seed?.category?.trim();
      final seededMerchant = seed?.merchantName?.trim();
      final seededNote = seed?.note?.trim();
      final seededAmount = seed?.amount;
      if (seededAccount != null && seededAccount.isNotEmpty) {
        _seededAccountName = seededAccount;
      }
      if (seededFromAccount != null && seededFromAccount.isNotEmpty) {
        _seededFromAccountName = seededFromAccount;
      }
      if (seededToAccount != null && seededToAccount.isNotEmpty) {
        _seededToAccountName = seededToAccount;
      }
      if (seededCategory != null && seededCategory.isNotEmpty) {
        if (_selectedType == TransactionType.expense &&
            !_expenseCategories.contains(seededCategory)) {
          _expenseCategories.add(seededCategory);
        }
        if (_categoriesFor(_selectedType).contains(seededCategory)) {
          _selectedCategory = seededCategory;
        }
      }
      if (seededMerchant != null && seededMerchant.isNotEmpty) {
        _selectedMerchant = seededMerchant;
      }
      if (seededNote != null && seededNote.isNotEmpty) {
        _note = seededNote;
      }
      if (seededAmount != null && seededAmount.isFinite && seededAmount > 0) {
        _amountText = _formatAmount(seededAmount);
        _startNewNumber = true;
      }
      if (_selectedType == TransactionType.transfer) {
        final fromSeed = _seededFromAccountName ?? _seededAccountName;
        if (fromSeed != null) _selectedFromAccount = fromSeed;
        if (_seededToAccountName != null) {
          _selectedToAccount = _seededToAccountName!;
        }
      } else if (_seededAccountName != null) {
        _selectedAccount = _seededAccountName!;
      }
      unawaited(_loadExpenseCategories());
      return;
    }

    _selectedType = record.type;
    _amountText = _formatAmount(record.amount);
    _selectedCategory = record.category;
    if (record.type == TransactionType.expense &&
        !_expenseCategories.contains(record.category)) {
      _expenseCategories.add(record.category);
    }
    _selectedTime = record.occurredAt;
    _selectedAccount = record.accountName;
    _selectedFromAccount = record.fromAccountName ?? record.accountName;
    _selectedToAccount = record.toAccountName ?? _selectedToAccount;
    _selectedMember = record.memberName;
    _selectedMerchant = record.merchantName;
    _selectedTag = record.tagName;
    _note = record.note;
    _selectedCurrency = record.currency;
    _exchangeRateText = _formatAmount(record.exchangeRateToBase);
    unawaited(_loadExpenseCategories());
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categoriesFor(_selectedType);
    final accountsState = ref.watch(accountListProvider);
    final activeAccounts = accountsState.valueOrNull?.where((account) => !account.isArchived).toList() ?? const <AccountRecord>[];
    final showInstallmentEntry = _canShowInstallmentEntry(activeAccounts);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '編輯記帳' : '新增記帳'),
        actions: [
          if (showInstallmentEntry)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: '轉為信用卡分期',
                child: TextButton.icon(
                  onPressed: _isSaving || _isOpeningInstallment ? null : _openInstallmentEntryFromCurrentForm,
                  icon: const Icon(Icons.splitscreen_outlined),
                  label: const Text('分期'),
                ),
              ),
            ),
          IconButton(
            tooltip: '記帳設定',
            onPressed: () => _showTopToast('記帳設定將於後續階段開放'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<TransactionType>(
              segments: TransactionType.values.map((type) => ButtonSegment<TransactionType>(value: type, label: Text(type.label))).toList(),
              selected: {_selectedType},
              onSelectionChanged: (selection) => _selectType(selection.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: _AmountCard(amountText: _amountText, expressionText: _expressionText, transactionType: _selectedType, category: _selectedCategory),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.96),
              itemBuilder: (context, index) {
                final category = categories[index];
                return _CategoryTile(label: category, selected: category == _selectedCategory, onTap: () => _selectCategory(category));
              },
            ),
          ),
          _NoteInputArea(note: _note, onTap: _editNote),
          if (widget.initialRecord != null)
            CloudInvoiceTransactionDetailSection(
              transaction: widget.initialRecord!,
              onSupplementRequested: _editInvoiceSupplement,
            ),
          accountsState.when(
            data: (accounts) {
              final accountOptions = _resolveAccounts(accounts);
              return _MetaActionBar(
                transactionType: _selectedType,
                selectedTime: _selectedTime,
                accountLabel: _selectedAccount,
                fromAccountLabel: _selectedFromAccount,
                toAccountLabel: _selectedToAccount,
                memberLabel: _selectedMember,
                merchantLabel: _selectedMerchant,
                tagLabel: _selectedTag,
                currency: _selectedCurrency,
                exchangeRateText: _exchangeRateText,
                onPickTime: _pickDateTime,
                onPickAccount: () => _showAccountChoiceSheet(title: '選擇帳戶', options: accountOptions, selected: _selectedAccount, onSelected: (value) => _selectAccount(value, accountOptions)),
                onPickFromAccount: () => _showAccountChoiceSheet(title: '選擇轉出帳戶', options: accountOptions, selected: _selectedFromAccount, onSelected: (value) => _selectTransferFrom(value, accountOptions)),
                onPickToAccount: () => _showAccountChoiceSheet(title: '選擇轉入帳戶', options: accountOptions, selected: _selectedToAccount, onSelected: (value) => _selectTransferTo(value, accountOptions)),
                onSwapTransferAccounts: () => _swapTransferAccounts(accountOptions),
                onPickMember: () => _showChoiceSheet(title: '選擇成員', options: _members, selected: _selectedMember, onSelected: (value) => setState(() => _selectedMember = value)),
                onPickMerchant: _showMerchantChoiceSheet,
                onPickTag: () => _showChoiceSheet(title: '選擇標籤', options: _tags, selected: _selectedTag, onSelected: (value) => setState(() => _selectedTag = value)),
                onEditRate: _editExchangeRate,
                onPickPhoto: () => _showTopToast('相機後續將支援紙本發票掃描與 AI 商品辨識'),
              );
            },
            loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
            error: (error, stackTrace) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(children: [
                Expanded(child: Text('帳戶讀取失敗：$error', maxLines: 1, overflow: TextOverflow.ellipsis)),
                TextButton(onPressed: () => ref.read(accountListProvider.notifier).load(), child: const Text('重試')),
              ]),
            ),
          ),
          _NumberPad(
            onKey: _handleCalculatorKey,
            onBackspace: _backspaceAmount,
            onClear: _clearAmount,
            onSave: _saveTransaction,
            isSaving: _isSaving || _isOpeningInstallment,
            isEditing: _isEditing || _savedNewRecord != null,
          ),
        ],
      ),
    );
  }

  void _selectType(TransactionType nextType) {
    setState(() {
      _selectedType = nextType;
      if (!_categoriesFor(nextType).contains(_selectedCategory)) _selectedCategory = _categoriesFor(nextType).first;
      if (nextType == TransactionType.transfer) {
        final fromSeed = _seededFromAccountName ?? _seededAccountName;
        if (fromSeed != null && fromSeed.isNotEmpty) {
          _selectedFromAccount = fromSeed;
        }
        final toSeed = _seededToAccountName;
        if (toSeed != null && toSeed.isNotEmpty) {
          _selectedToAccount = toSeed;
        }
      } else {
        final accountSeed = _seededAccountName;
        if (accountSeed != null && accountSeed.isNotEmpty) {
          _selectedAccount = accountSeed;
        }
      }
    });
  }

  bool _canShowInstallmentEntry(List<AccountRecord> accounts) {
    if (_selectedType != TransactionType.expense) return false;
    final rawAmount = double.tryParse(_amountText) ?? 0;
    if (_selectedCurrency.roundAmount(rawAmount.abs()) <= 0) return false;
    final account = _findAccount(accounts, _selectedAccount);
    return account != null && account.type == AccountType.creditCard;
  }

  void _selectCategory(String category) => setState(() => _selectedCategory = category);

  Future<void> _openInstallmentEntryFromCurrentForm() async {
    if (_isOpeningInstallment || _isSaving) return;
    _calculateResult();
    final accounts = ref.read(accountListProvider).valueOrNull?.where((account) => !account.isArchived).toList() ?? const <AccountRecord>[];
    final card = _findAccount(accounts, _selectedAccount);
    if (_selectedType != TransactionType.expense || card == null || card.type != AccountType.creditCard) {
      _showTopToast('請先選擇信用卡支出');
      return;
    }
    final record = _buildCurrentRecord();
    if (record == null) return;
    setState(() => _isOpeningInstallment = true);
    try {
      await _persistRecord(record);
      _savedNewRecord = record;
      ref.invalidate(accountListProvider);
      if (!mounted) return;
      await _showSourceTransactionInstallmentSheet(record, card);
    } catch (error) {
      if (mounted) _showTopToast('開啟分期失敗：$error');
    } finally {
      if (mounted) setState(() => _isOpeningInstallment = false);
    }
  }

  Future<void> _showSourceTransactionInstallmentSheet(TransactionRecord record, AccountRecord card) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
          child: SourceTransactionInstallmentEntryCard(
            transaction: record,
            card: card,
            onPlanCreated: (plan) {
              Navigator.of(context).pop();
              _showTopToast('已建立分期計畫');
            },
          ),
        ),
      ),
    );
  }

  List<AccountRecord> _resolveAccounts(List<AccountRecord> accounts) {
    final items = accounts.where((account) => !account.isArchived).toList();
    if (items.isEmpty) return const [];
    final names = items.map((account) => account.displayName).toList();
    _ensureSelectedAccountExists(names);
    _syncCurrencyFromAccount(items);
    return items;
  }

  AccountRecord? _findAccount(List<AccountRecord> accounts, String displayName) {
    for (final account in accounts) {
      if (account.displayName == displayName) return account;
    }
    return null;
  }

  void _syncCurrencyFromAccount(List<AccountRecord> accounts) {
    final account = _selectedType == TransactionType.transfer ? _transferFxAccount(accounts) : _findAccount(accounts, _selectedAccount);
    if (account == null) return;
    if (_selectedCurrency == account.currency && _exchangeRateText.trim().isNotEmpty) return;
    _selectedCurrency = account.currency;
    _exchangeRateText = _formatAmount(account.currency.defaultRateToTwd);
  }

  AccountRecord? _transferFxAccount(List<AccountRecord> accounts) {
    final from = _findAccount(accounts, _selectedFromAccount);
    final to = _findAccount(accounts, _selectedToAccount);
    if (from != null && from.currency != CurrencyCode.twd) return from;
    if (to != null && to.currency != CurrencyCode.twd) return to;
    return from ?? to;
  }

  void _ensureSelectedAccountExists(List<String> names) {
    if (!names.contains(_selectedAccount)) _selectedAccount = names.first;

    final fromSeed = _seededFromAccountName ?? _seededAccountName;
    if (!names.contains(_selectedFromAccount)) {
      _selectedFromAccount = fromSeed != null && names.contains(fromSeed)
          ? fromSeed
          : names.first;
    }

    final toSeed = _seededToAccountName;
    if (!names.contains(_selectedToAccount)) {
      _selectedToAccount = toSeed != null && names.contains(toSeed)
          ? toSeed
          : names.length > 1
              ? names.firstWhere(
                  (name) => name != _selectedFromAccount,
                  orElse: () => names.first,
                )
              : names.first;
    }

    if (_selectedType == TransactionType.transfer &&
        _selectedFromAccount == _selectedToAccount &&
        names.length > 1) {
      if (toSeed != null && names.contains(toSeed)) {
        _selectedFromAccount = names.firstWhere(
          (name) => name != _selectedToAccount,
          orElse: () => names.first,
        );
      } else {
        _selectedToAccount = names.firstWhere(
          (name) => name != _selectedFromAccount,
          orElse: () => names.first,
        );
      }
    }
  }

  void _selectAccount(String value, List<AccountRecord> accounts) {
    final account = _findAccount(accounts, value) ?? accounts.first;
    setState(() {
      _selectedAccount = value;
      _selectedCurrency = account.currency;
      _exchangeRateText = _formatAmount(account.currency.defaultRateToTwd);
    });
  }

  void _selectTransferFrom(String value, List<AccountRecord> accounts) {
    setState(() {
      _selectedFromAccount = value;
      _applyTransferCurrency(accounts);
    });
  }

  void _selectTransferTo(String value, List<AccountRecord> accounts) {
    setState(() {
      _selectedToAccount = value;
      _applyTransferCurrency(accounts);
    });
  }

  void _swapTransferAccounts(List<AccountRecord> accounts) {
    setState(() {
      final oldFrom = _selectedFromAccount;
      _selectedFromAccount = _selectedToAccount;
      _selectedToAccount = oldFrom;
      _applyTransferCurrency(accounts);
    });
  }

  void _applyTransferCurrency(List<AccountRecord> accounts) {
    final account = _transferFxAccount(accounts);
    if (account == null) return;
    _selectedCurrency = account.currency;
    _exchangeRateText = _formatAmount(account.currency.defaultRateToTwd);
  }

  Future<void> _loadExpenseCategories() async {
    try {
      final records = await ExpenseCategoryRepository.instance.listActive();
      if (!mounted) return;
      final selected = _selectedCategory;
      final next = _normalizeChoiceOptions([
        ...canonicalDefaultExpenseCategories,
        ...records.map((record) => record.name),
        if (selected.trim().isNotEmpty) selected,
      ]);
      setState(() {
        _expenseCategories
          ..clear()
          ..addAll(next);
      });
    } catch (_) {
      // Keep the built-in canonical defaults when the additive category table
      // cannot be read. This does not affect formal transaction write safety.
    }
  }

  List<String> _categoriesFor(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return _expenseCategories;
      case TransactionType.income:
        return _incomeCategories;
      case TransactionType.transfer:
        return _transferCategories;
      case TransactionType.loan:
        return _loanCategories;
    }
  }

  void _handleCalculatorKey(String value) {
    if (value == '±') return _toggleSign();
    if (['+', '-', '×', '÷'].contains(value)) return _setOperator(value);
    if (value == '=') return _calculateResult();
    _appendAmount(value);
  }

  void _appendAmount(String value) {
    setState(() {
      if (_startNewNumber || _amountText == '0.00' || _amountText == '0') {
        _amountText = value == '.' ? '0.' : value;
        _startNewNumber = false;
        return;
      }
      if (value == '.' && _amountText.contains('.')) return;
      _amountText += value;
    });
  }

  void _setOperator(String operator) {
    final currentValue = double.tryParse(_amountText) ?? 0;
    setState(() {
      if (_operand != null && _operator != null && !_startNewNumber) {
        _operand = _applyOperator(_operand!, currentValue, _operator!);
      } else {
        _operand = currentValue;
      }
      _operator = operator;
      _expressionText = '${_formatAmount(_operand!)} $operator';
      _amountText = '0.00';
      _startNewNumber = true;
    });
  }

  void _calculateResult() {
    final currentValue = double.tryParse(_amountText) ?? 0;
    if (_operand == null || _operator == null) return;
    setState(() {
      final result = _applyOperator(_operand!, currentValue, _operator!);
      _amountText = _formatAmount(_selectedCurrency.roundAmount(result));
      _operand = null;
      _operator = null;
      _expressionText = '';
      _startNewNumber = true;
    });
  }

  double _applyOperator(double left, double right, String operator) {
    switch (operator) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case '×':
        return left * right;
      case '÷':
        if (right == 0) {
          _showTopToast('不能除以 0');
          return left;
        }
        return left / right;
      default:
        return right;
    }
  }

  void _toggleSign() {
    final value = double.tryParse(_amountText) ?? 0;
    setState(() => _amountText = _formatAmount(value * -1));
  }

  void _backspaceAmount() {
    setState(() {
      if (_startNewNumber || _amountText.length <= 1 || (_amountText.startsWith('-') && _amountText.length <= 2)) {
        _amountText = '0.00';
        _startNewNumber = true;
        return;
      }
      _amountText = _amountText.substring(0, _amountText.length - 1);
    });
  }

  void _clearAmount() {
    setState(() {
      _amountText = '0.00';
      _expressionText = '';
      _operand = null;
      _operator = null;
      _startNewNumber = true;
    });
  }

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _pickDateTime() async {
    var draft = _selectedTime;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void updateDraft({int? year, int? month, int? day, int? hour, int? minute}) {
            final nextYear = year ?? draft.year;
            final nextMonth = month ?? draft.month;
            final maxDay = DateUtils.getDaysInMonth(nextYear, nextMonth);
            final nextDay = (day ?? draft.day).clamp(1, maxDay).toInt();
            draft = DateTime(nextYear, nextMonth, nextDay, hour ?? draft.hour, minute ?? draft.minute);
            setModalState(() {});
          }

          Future<void> openCalendar() async {
            final date = await showDatePicker(context: context, initialDate: draft, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (date == null) return;
            updateDraft(year: date.year, month: date.month, day: date.day);
          }

          Future<void> openClock() async {
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(draft));
            if (time == null) return;
            updateDraft(hour: time.hour, minute: time.minute);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('調整日期時間', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Semantics(
                  label: '日期選取列',
                  child: Row(children: [
                    Expanded(child: _WheelPicker(label: '年', min: 2020, max: 2100, value: draft.year, onChanged: (value) => updateDraft(year: value))),
                    Expanded(child: _WheelPicker(label: '月', min: 1, max: 12, value: draft.month, onChanged: (value) => updateDraft(month: value))),
                    Expanded(child: _WheelPicker(label: '日', min: 1, max: DateUtils.getDaysInMonth(draft.year, draft.month), value: draft.day, onChanged: (value) => updateDraft(day: value))),
                    Expanded(child: _WeekdayDisplay(date: draft)),
                  ]),
                ),
                const Divider(height: 18),
                Semantics(
                  label: '時間選取列',
                  child: Row(children: [
                    Expanded(child: _WheelPicker(label: '時', min: 0, max: 23, value: draft.hour, pad: 2, onChanged: (value) => updateDraft(hour: value))),
                    Expanded(child: _WheelPicker(label: '分', min: 0, max: 59, value: draft.minute, pad: 2, onChanged: (value) => updateDraft(minute: value))),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: openCalendar, icon: const Icon(Icons.calendar_month), label: const Text('月曆'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: openClock, icon: const Icon(Icons.schedule), label: const Text('時鐘'))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(draft), child: const Text('套用'))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedTime = picked);
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('輸入備註'),
        content: TextField(controller: controller, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: '可輸入備註；後續雲端發票明細也會整合於此區')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('套用')),
        ],
      ),
    );
    if (value == null) return;
    setState(() => _note = value);
  }

  Future<void> _editInvoiceSupplement() async {
    final controller = TextEditingController(
      text: CloudInvoiceSupplementNote.extract(_note),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('補充未列入發票明細'),
        content: TextField(
          key: const Key('cloud_invoice_supplement_note_field'),
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '例如：第 101 項 商品名稱／金額；第 102 項…',
            helperText: '補充內容會存入正式交易備註，不會改寫官方發票明細。',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('清除補充'),
          ),
          FilledButton(
            key: const Key('cloud_invoice_supplement_note_apply'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('套用補充'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() {
      _note = CloudInvoiceSupplementNote.replace(_note, value);
    });
    _showTopToast(
      value.trim().isEmpty ? '已清除未列入明細補充' : '已加入未列入明細補充，請儲存交易',
    );
  }

  Future<void> _editExchangeRate() async {
    final controller = TextEditingController(text: _exchangeRateText);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改匯率'),
        content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '1 ${_selectedCurrency.code} = ? TWD')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('套用')),
        ],
      ),
    );
    if (value == null || double.tryParse(value) == null) return;
    setState(() => _exchangeRateText = value);
  }

  Future<void> _showAccountChoiceSheet({
    required String title,
    required List<AccountRecord> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) async {
    if (options.isEmpty) {
      _showNoAccountSheet();
      return;
    }
    final picked = await showGroupedAccountChoiceSheet(
      context,
      title: title,
      accounts: options,
      selectedDisplayName: selected,
    );
    if (picked == null || !mounted) return;
    onSelected(picked.displayName);
  }

  Future<void> _showMerchantChoiceSheet() async {
    var options = _merchants;
    try {
      final records = await CanonicalMerchantRepository.instance.listMerchants();
      options = _normalizeChoiceOptions([..._merchants, ...records.map((record) => record.displayName)]);
    } catch (_) {
      options = _merchants;
    }
    if (!mounted) return;
    await _showChoiceSheet(
      title: '選擇商家',
      options: options,
      selected: _selectedMerchant,
      onSelected: (value) => setState(() => _selectedMerchant = value),
    );
  }

  Future<void> _showNoAccountSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('尚未建立可用帳戶', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('請先到帳戶管理新增至少一個帳戶，再回來記帳。'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('稍後'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () { Navigator.of(context).pop(); context.pushNamed(AccountPage.routeName); }, child: const Text('前往帳戶'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _showChoiceSheet({required String title, required List<String> options, required String selected, required ValueChanged<String> onSelected}) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final option in options)
                  ListTile(
                    title: Text(option),
                    trailing: option == selected ? const Icon(Icons.check) : null,
                    onTap: () { onSelected(option); Navigator.of(context).pop(); },
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  TransactionRecord? _buildCurrentRecord() {
    final rawAmount = double.tryParse(_amountText) ?? 0;
    final amount = _selectedCurrency.roundAmount(rawAmount.abs());
    final rate = double.tryParse(_exchangeRateText) ?? _selectedCurrency.defaultRateToTwd;
    if (amount == 0) {
      _showTopToast('請輸入金額');
      return null;
    }
    final original = widget.initialRecord ?? _savedNewRecord;
    return TransactionRecord(
      id: original?.id ?? const Uuid().v4(),
      type: _selectedType,
      amount: amount,
      category: _selectedCategory,
      occurredAt: _selectedTime,
      accountName: _selectedType == TransactionType.transfer ? _selectedFromAccount : _selectedAccount,
      memberName: _selectedMember,
      merchantName: _selectedType == TransactionType.transfer ? '' : _selectedMerchant,
      tagName: _selectedTag,
      note: _note,
      currency: _selectedCurrency,
      exchangeRateToBase: rate,
      fromAccountName: _selectedType == TransactionType.transfer ? _selectedFromAccount : null,
      toAccountName: _selectedType == TransactionType.transfer ? _selectedToAccount : null,
    );
  }

  Future<void> _persistRecord(TransactionRecord record) async {
    if (widget.initialRecord != null || _savedNewRecord != null) {
      await ref.read(transactionLedgerProvider.notifier).updateRecord(record);
    } else {
      await ref.read(transactionLedgerProvider.notifier).add(record);
    }
  }

  Future<void> _saveTransaction() async {
    if (_isSaving) return;
    _calculateResult();
    final record = _buildCurrentRecord();
    if (record == null) return;
    final accounts = ref.read(accountListProvider).valueOrNull?.where((account) => !account.isArchived).toList() ?? const <AccountRecord>[];
    if (accounts.isEmpty) {
      await _showNoAccountSheet();
      return;
    }
    final wasExisting = widget.initialRecord != null || _savedNewRecord != null;
    setState(() => _isSaving = true);
    try {
      await _persistRecord(record);
      _savedNewRecord = record;
      ref.invalidate(accountListProvider);
      if (!mounted) return;
      _showTopToast(wasExisting ? '已更新記帳' : '已保存記帳');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showTopToast('${wasExisting ? '更新' : '保存'}失敗：$error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showTopToast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Center(child: Text(message, textAlign: TextAlign.center)),
        duration: const Duration(milliseconds: 850),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 24, right: 24, bottom: MediaQuery.sizeOf(context).height - 132),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

List<String> _normalizeChoiceOptions(Iterable<String> values) {
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

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amountText, required this.expressionText, required this.transactionType, required this.category});
  final String amountText;
  final String expressionText;
  final TransactionType transactionType;
  final String category;

  @override
  Widget build(BuildContext context) {
    final color = transactionType == TransactionType.income ? Colors.deepOrange : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: 0.14), child: Icon(Icons.receipt_long, color: color, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(transactionType.label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)), Text(category, style: Theme.of(context).textTheme.bodySmall)])),
          if (expressionText.isNotEmpty) Flexible(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text(expressionText, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall))),
          Flexible(child: Text(amountText, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircleAvatar(radius: 21, backgroundColor: color.withValues(alpha: selected ? 1 : 0.14), child: Icon(Icons.category_outlined, color: selected ? Colors.white : color, size: 20)),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _NoteInputArea extends StatelessWidget {
  const _NoteInputArea({required this.note, required this.onTap});
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
          child: Row(children: [
            const Icon(Icons.notes_outlined, size: 18),
            const SizedBox(width: 8),
            const Text('備註 / 發票明細'),
            const SizedBox(width: 8),
            Expanded(child: Text(note.isEmpty ? '補充說明' : note, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: note.isEmpty ? Colors.blueGrey : null))),
          ]),
        ),
      ),
    );
  }
}

class _MetaActionBar extends StatelessWidget {
  const _MetaActionBar({required this.transactionType, required this.selectedTime, required this.accountLabel, required this.fromAccountLabel, required this.toAccountLabel, required this.memberLabel, required this.merchantLabel, required this.tagLabel, required this.currency, required this.exchangeRateText, required this.onPickTime, required this.onPickAccount, required this.onPickFromAccount, required this.onPickToAccount, required this.onSwapTransferAccounts, required this.onPickMember, required this.onPickMerchant, required this.onPickTag, required this.onEditRate, required this.onPickPhoto});

  final TransactionType transactionType;
  final DateTime selectedTime;
  final String accountLabel;
  final String fromAccountLabel;
  final String toAccountLabel;
  final String memberLabel;
  final String merchantLabel;
  final String tagLabel;
  final CurrencyCode currency;
  final String exchangeRateText;
  final VoidCallback onPickTime;
  final VoidCallback onPickAccount;
  final VoidCallback onPickFromAccount;
  final VoidCallback onPickToAccount;
  final VoidCallback onSwapTransferAccounts;
  final VoidCallback onPickMember;
  final VoidCallback onPickMerchant;
  final VoidCallback onPickTag;
  final VoidCallback onEditRate;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final dateLabel = '${selectedTime.year}/${selectedTime.month.toString().padLeft(2, '0')}/${selectedTime.day.toString().padLeft(2, '0')} ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
    final isTransfer = transactionType == TransactionType.transfer;
    final row1 = isTransfer
        ? <Widget>[_AutoMetaChip(label: dateLabel, onPressed: onPickTime), _AutoMetaChip(label: memberLabel, onPressed: onPickMember), _AutoMetaChip(label: tagLabel, onPressed: onPickTag)]
        : <Widget>[_AutoMetaChip(label: dateLabel, onPressed: onPickTime), _AutoMetaChip(label: accountLabel, onPressed: onPickAccount)];
    final row2 = isTransfer
        ? <Widget>[_AutoMetaChip(label: fromAccountLabel, onPressed: onPickFromAccount), _SwapChip(onPressed: onSwapTransferAccounts), _AutoMetaChip(label: toAccountLabel, onPressed: onPickToAccount), _AutoMetaChip(label: '1 ${currency.code} = $exchangeRateText TWD', onPressed: onEditRate)]
        : <Widget>[_AutoMetaChip(label: memberLabel, onPressed: onPickMember), _AutoMetaChip(label: merchantLabel, onPressed: onPickMerchant), _AutoMetaChip(label: tagLabel, onPressed: onPickTag), _AutoMetaChip(label: '1 ${currency.code} = $exchangeRateText TWD', onPressed: onEditRate)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: row1),
              const SizedBox(height: 4),
              Row(children: row2),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 44, height: 84, child: IconButton.filledTonal(tooltip: '拍照附件', onPressed: onPickPhoto, icon: const Icon(Icons.camera_alt_outlined))),
      ]),
    );
  }
}

class _AutoMetaChip extends StatelessWidget {
  const _AutoMetaChip({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis), onPressed: onPressed, visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap));
}

class _SwapChip extends StatelessWidget {
  const _SwapChip({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(avatar: const Icon(Icons.swap_horiz, size: 18), label: const Text('互換'), onPressed: onPressed, visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap));
}

class _WeekdayDisplay extends StatelessWidget {
  const _WeekdayDisplay({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final colorScheme = Theme.of(context).colorScheme;
    final label = labels[date.weekday - 1];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('星期', style: Theme.of(context).textTheme.labelLarge),
      SizedBox(
        height: 104,
        child: Center(
          child: Semantics(
            label: '星期$label',
            child: Container(
              width: 58,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18), border: Border.all(color: colorScheme.primary.withValues(alpha: 0.32))),
              child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w900, height: 1.0)),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _WheelPicker extends StatefulWidget {
  const _WheelPicker({required this.label, required this.min, required this.max, required this.value, required this.onChanged, this.pad = 0});
  final String label;
  final int min;
  final int max;
  final int value;
  final int pad;
  final ValueChanged<int> onChanged;

  @override
  State<_WheelPicker> createState() => _WheelPickerState();
}

class _WheelPickerState extends State<_WheelPicker> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: (widget.value - widget.min).clamp(0, widget.max - widget.min).toInt());
  }

  @override
  void didUpdateWidget(covariant _WheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _controller.dispose();
      _controller = FixedExtentScrollController(initialItem: (widget.value - widget.min).clamp(0, widget.max - widget.min).toInt());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
      SizedBox(
        height: 104,
        child: ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: 32,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (index) => widget.onChanged(widget.min + index),
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: widget.max - widget.min + 1,
            builder: (context, index) {
              final value = widget.min + index;
              final isSelected = value == widget.value;
              return Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  style: (isSelected ? Theme.of(context).textTheme.headlineSmall : Theme.of(context).textTheme.titleMedium)!.copyWith(color: isSelected ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.78), fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500, height: 1.0),
                  child: Text(value.toString().padLeft(widget.pad, '0')),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.onKey, required this.onBackspace, required this.onClear, required this.onSave, required this.isSaving, required this.isEditing});
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final bool isSaving;
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    const rows = [['1', '2', '3', '+'], ['4', '5', '6', '-'], ['7', '8', '9', '×'], ['.', '0', '=', '÷']];
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(
              flex: 4,
              child: Column(children: [
                for (final row in rows)
                  Expanded(
                    child: Row(children: [
                      for (final key in row)
                        Expanded(child: Padding(padding: const EdgeInsets.all(2), child: _KeyButton(label: key, isPrimary: key == '=', onPressed: isSaving ? null : () => onKey(key)))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _SideActionButton(icon: Icons.backspace_outlined, label: '刪除', onPressed: isSaving ? null : onBackspace)),
                Expanded(child: _SideActionButton(icon: Icons.cleaning_services_outlined, label: '清除', onPressed: isSaving ? null : onClear)),
                Expanded(child: TextButton(onPressed: isSaving ? null : () => onKey('±'), child: const Text('+/-'))),
                Expanded(child: FilledButton(onPressed: isSaving ? null : onSave, child: Text(isSaving ? '保存中' : isEditing ? '更新' : '保存', textAlign: TextAlign.center))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, required this.onPressed, this.isPrimary = false});
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) => isPrimary ? FilledButton.tonal(onPressed: onPressed, child: Text(label, style: const TextStyle(fontSize: 22))) : TextButton(onPressed: onPressed, child: Text(label, style: const TextStyle(fontSize: 22)));
}

class _SideActionButton extends StatelessWidget {
  const _SideActionButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label), style: TextButton.styleFrom(padding: EdgeInsets.zero));
}
