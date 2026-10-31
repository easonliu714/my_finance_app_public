import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../plan/credit_card_payment_flow.dart';
import '../plan/credit_card_statement_service.dart';
import '../plan/loan_repayment_flow.dart';
import '../transaction/transaction_entry_page.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'account_providers.dart';
import 'account_record.dart';
import 'debit_card_available_balance_panel.dart';
import 'debit_card_available_balance_providers.dart';
import 'debit_card_settlement_panel.dart';
import 'debit_card_settlement_providers.dart';

class AccountDetailPage extends ConsumerStatefulWidget {
  const AccountDetailPage({super.key, required this.account});

  static const routeName = 'account-detail';
  static const routePath = '/accounts/detail';

  final AccountRecord account;

  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends ConsumerState<AccountDetailPage> {
  // Track the real rendered SliverList children, not a nominal fixed row height.
  final GlobalKey _ledgerSliverKey = GlobalKey();
  final GlobalKey _pinnedSummaryKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  bool _anchorCheckQueued = false;
  List<AccountLedgerItem> _visibleOrderItems = const [];
  DateTime? _anchorDate;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleAnchorSync);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scheduleAnchorSync);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final detail = ref.watch(accountDetailProvider(account));
    final allAccounts =
        ref.watch(accountListProvider).valueOrNull ?? const <AccountRecord>[];
    final loanAccounts = allAccounts
        .where((item) => item.type == AccountType.loan && !item.isArchived)
        .toList();
    final creditCardAccounts = allAccounts
        .where(
          (item) =>
              item.type == AccountType.creditCard && !item.isArchived,
        )
        .toList();
    final ledgerRecords =
        ref.watch(transactionLedgerProvider).valueOrNull?.records ??
            const <TransactionRecord>[];
    final supportsSettlementPanel = _supportsAvailableBalance(account);
    final settlementValue = supportsSettlementPanel
        ? ref.watch(
            accountDebitCardSettlementPresentationProvider(account),
          )
        : null;
    if (supportsSettlementPanel) {
      ref.watch(debitCardSettlementReminderReconciliationProvider);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(account.displayName),
        actions: [
          if (_isTopUpAccount(account))
            TextButton.icon(
              onPressed: () => _openTopUpEntry(context, account),
              icon: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
              ),
              label: const Text('儲值'),
            )
          else if (account.type != AccountType.loan &&
              account.type != AccountType.creditCard)
            TextButton.icon(
              onPressed: () => _showRepaymentTargetSheet(
                context,
                loanAccounts,
                creditCardAccounts,
                allAccounts,
                ledgerRecords,
              ),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('還款'),
            ),
          if (account.type == AccountType.creditCard)
            TextButton.icon(
              onPressed: () => _openCreditCardPaymentFlow(
                context,
                [account],
                allAccounts,
                ledgerRecords,
                initialCard: account,
              ),
              icon: const Icon(Icons.credit_card, size: 18),
              label: const Text('繳款'),
            ),
          TextButton.icon(
            onPressed: () => _showBalanceCorrectionSheet(context, ref),
            icon: const Icon(Icons.balance_outlined, size: 18),
            label: const Text('餘額校正'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (account.type == AccountType.loan) {
            await _openLoanRepaymentFlow(
              context,
              [account],
              allAccounts,
              ledgerRecords,
              initialLoan: account,
            );
          } else {
            await _openStandardEntry(context, account);
          }
          ref.invalidate(accountDetailProvider(account));
          ref.invalidate(accountListProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(account.type == AccountType.loan ? '還一筆' : '記一筆'),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('讀取帳戶明細失敗：$error')),
        data: (state) {
          final ledgerItems = state.items.reversed.toList(growable: false);
          _visibleOrderItems = ledgerItems;
          // A refresh or filter change may change the first visible row even
          // without a scroll event. Re-anchor after that layout completes.
          _scheduleAnchorSync();
          final defaultAnchor = ledgerItems.isEmpty
              ? DateTime.now()
              : ledgerItems.first.occurredAt;
          final anchor = _anchorDate ?? defaultAnchor;
          final yearSummary = state.summaryFor(
            year: anchor.year,
            label: '${anchor.year}年',
          );
          final monthSummary = state.summaryFor(
            year: anchor.year,
            month: anchor.month,
            label: '${anchor.month.toString().padLeft(2, '0')}月',
          );
          return RefreshIndicator(
            onRefresh: () => _refreshAccount(account),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _BalanceHeader(state: state),
                  ),
                ),
                if (settlementValue != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: DebitCardSettlementPanel(
                        account: account,
                        value: settlementValue,
                      ),
                    ),
                  ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _AccountSummaryHeaderDelegate(
                    // Two distinct summary heading lines need real layout space,
                    // including when Android users enlarge their display text.
                    minExtentValue: MediaQuery.textScalerOf(context).scale(172.0),
                    maxExtentValue: MediaQuery.textScalerOf(context).scale(172.0),
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Padding(
                        key: _pinnedSummaryKey,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _CompactPeriodSummaryCard(
                                summary: yearSummary,
                                currency: account.currency,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactPeriodSummaryCard(
                                summary: monthSummary,
                                currency: account.currency,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '日明細',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '統計跟隨畫面第一筆',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ),
                if (ledgerItems.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('尚無帳戶明細。'),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: SliverList(
                      key: _ledgerSliverKey,
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = ledgerItems[index];
                          return _AccountLedgerTile(
                            key: ValueKey<String>(item.id),
                            item: item,
                            currency: account.currency,
                            onEdit: () => _handleEdit(context, ref, item),
                            onDuplicate: () =>
                                _handleDuplicate(context, ref, item),
                            onDelete: () => _handleDelete(context, ref, item),
                          );
                        },
                        childCount: ledgerItems.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshAccount(AccountRecord account) async {
    await ref.read(accountDetailProvider(account).notifier).load();
    if (!_supportsAvailableBalance(account)) return;
    ref.invalidate(accountAvailableBalancePresentationProvider(account));
    ref.invalidate(
      accountDebitCardSettlementPresentationProvider(account),
    );
    ref.invalidate(debitCardSettlementReminderReconciliationProvider);
    try {
      await ref.read(
        accountAvailableBalancePresentationProvider(account).future,
      );
    } catch (_) {
      // The available-balance panel renders a non-blocking error state.
    }
    try {
      await ref.read(
        accountDebitCardSettlementPresentationProvider(account).future,
      );
    } catch (_) {
      // The settlement panel renders a fail-closed relationship error.
    }
  }

  bool _supportsAvailableBalance(AccountRecord account) {
    return account.type == AccountType.debitCard ||
        account.type == AccountType.bank;
  }

  bool _isTopUpAccount(AccountRecord account) {
    return account.type == AccountType.storedValue ||
        account.type == AccountType.eWallet;
  }

  Future<void> _openStandardEntry(
    BuildContext context,
    AccountRecord account,
  ) async {
    await context.pushNamed(
      TransactionEntryPage.routeName,
      extra: TransactionEntrySeed(
        accountName: account.displayName,
        initialType: TransactionType.expense,
      ),
    );
    if (!mounted) return;
    ref.invalidate(accountDetailProvider(account));
    ref.invalidate(accountListProvider);
    ref.invalidate(transactionLedgerProvider);
  }

  Future<void> _openTopUpEntry(
    BuildContext context,
    AccountRecord account,
  ) async {
    await context.pushNamed(
      TransactionEntryPage.routeName,
      extra: TransactionEntrySeed(
        toAccountName: account.displayName,
        initialType: TransactionType.transfer,
      ),
    );
    if (!mounted) return;
    ref.invalidate(accountDetailProvider(account));
    ref.invalidate(accountListProvider);
    ref.invalidate(transactionLedgerProvider);
  }

  Future<void> _showRepaymentTargetSheet(
    BuildContext context,
    List<AccountRecord> loans,
    List<AccountRecord> creditCards,
    List<AccountRecord> accounts,
    List<TransactionRecord> transactions,
  ) async {
    if (loans.isEmpty && creditCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未建立借貸或信用卡帳戶')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Text(
              '選擇還款對象',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (creditCards.isNotEmpty) ...[
              Text(
                '信用卡',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              for (final card in creditCards)
                ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: Text(card.displayName),
                  subtitle: const Text('信用卡繳款'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openCreditCardPaymentFlow(
                      context,
                      [card],
                      accounts,
                      transactions,
                      initialCard: card,
                    );
                  },
                ),
            ],
            if (loans.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '借貸',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              for (final loan in loans)
                ListTile(
                  leading: const Icon(Icons.request_quote_outlined),
                  title: Text(loan.displayName),
                  subtitle: const Text('借貸還款'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openLoanRepaymentFlow(
                      context,
                      [loan],
                      accounts,
                      transactions,
                      initialLoan: loan,
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openLoanRepaymentFlow(
    BuildContext context,
    List<AccountRecord> loans,
    List<AccountRecord> accounts,
    List<TransactionRecord> transactions, {
    AccountRecord? initialLoan,
  }) async {
    await showLoanRepaymentFlow(
      context: context,
      ref: ref,
      loans: loans,
      accounts: accounts,
      transactions: transactions,
      sourceAccount:
          widget.account.type == AccountType.loan ? null : widget.account,
      initialLoan: initialLoan,
    );
    if (!mounted) return;
    ref.invalidate(accountDetailProvider(widget.account));
    ref.invalidate(accountListProvider);
    ref.invalidate(transactionLedgerProvider);
  }

  Future<void> _openCreditCardPaymentFlow(
    BuildContext context,
    List<AccountRecord> creditCards,
    List<AccountRecord> accounts,
    List<TransactionRecord> transactions, {
    AccountRecord? initialCard,
  }) async {
    final card =
        initialCard ?? (creditCards.isNotEmpty ? creditCards.first : null);
    final estimate = card == null
        ? null
        : buildCreditCardStatementEstimate(card, transactions);
    await showCreditCardPaymentFlow(
      context: context,
      ref: ref,
      creditCards: creditCards,
      accounts: accounts,
      sourceAccount: widget.account.type == AccountType.creditCard ||
              widget.account.type == AccountType.loan
          ? null
          : widget.account,
      initialCard: initialCard,
      initialEstimate: estimate,
    );
    if (!mounted) return;
    ref.invalidate(accountDetailProvider(widget.account));
    ref.invalidate(accountListProvider);
    ref.invalidate(transactionLedgerProvider);
  }

  // Scroll listeners run before sliver layout. Schedule a single geometry
  // inspection after layout to track the correct first visible transaction.
  void _scheduleAnchorSync() {
    if (_anchorCheckQueued || !mounted) return;
    _anchorCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorCheckQueued = false;
      if (mounted) _syncAnchorFromScroll();
    });
  }

  void _syncAnchorFromScroll() {
    if (!mounted || _visibleOrderItems.isEmpty || !_scrollController.hasClients) {
      return;
    }
    // Only the mounted sliver's actual child geometry is authoritative.
    // This works for variable-height, expanded and text-scaled rows.
    final sliver = _ledgerSliverKey.currentContext?.findRenderObject();
    if (sliver is! RenderSliverList || sliver.geometry == null) return;
    final summary = _pinnedSummaryKey.currentContext?.findRenderObject();
    if (summary is! RenderBox || !summary.hasSize) return;
    final visibleTop = summary.localToGlobal(
      Offset(0, summary.size.height),
    ).dy;
    final visibleBottom = MediaQuery.sizeOf(context).height;
    RenderBox? row = sliver.firstChild;
    DateTime? next;
    while (row != null) {
      final bottom = row.localToGlobal(Offset(0, row.size.height)).dy;
      final top = row.localToGlobal(Offset.zero).dy;
      if (bottom > visibleTop + 1 && top < visibleBottom) {
        final index = sliver.indexOf(row);
        if (index >= 0 && index < _visibleOrderItems.length) {
          next = _visibleOrderItems[index].occurredAt;
        }
        break;
      }
      row = sliver.childAfter(row);
    }
    if (next == null) return;
    final current = _anchorDate;
    if (current != null &&
        current.year == next.year && current.month == next.month) {
      return;
    }
    setState(() => _anchorDate = next);
  }

  Future<void> _showBalanceCorrectionSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state =
        ref.read(accountDetailProvider(widget.account)).valueOrNull;
    final current = state?.currentBalance ?? 0;
    final controller = TextEditingController(text: _compactNumber(current));
    final noteController = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '餘額校正',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '目前統計餘額：${_money(current, widget.account.currency)}',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '校正後餘額'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: '備註',
                hintText: '例如：補登漏記、與銀行餘額校正',
              ),
            ),
            const SizedBox(height: 12),
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
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('建立校正'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final corrected = double.tryParse(controller.text.trim());
    if (corrected == null) return;
    final diff = corrected - current;
    if (!context.mounted) return;
    final ok = await _confirmSensitive(
      context,
      '餘額差異為 ${_money(diff, widget.account.currency)}。'
      '建立校正記錄後會影響此帳戶後續統計，是否確認？',
    );
    if (!ok) return;
    await ref
        .read(accountDetailProvider(widget.account).notifier)
        .addBalanceCorrection(
          corrected,
          note: noteController.text.trim(),
        );
    ref.invalidate(accountListProvider);
  }

  Future<void> _handleEdit(
    BuildContext context,
    WidgetRef ref,
    AccountLedgerItem item,
  ) async {
    if (item.isSensitiveEvent) {
      await _confirmSensitive(
        context,
        '初始值設定與餘額校正會影響帳戶統計；本階段先不開放直接編輯，'
        '請使用新增校正記錄修正。',
      );
      return;
    }
    if (item.transaction?.isLoanRepayment == true ||
        item.isLoanRepaymentCandidate) {
      await _confirmSensitive(
        context,
        '還款群組會影響本金與利息紀錄；本階段先不開放直接編輯，'
        '請刪除整組後重新建立。',
      );
      return;
    }
    final tx = item.transaction;
    if (tx != null && context.mounted) {
      await context.pushNamed(TransactionEntryPage.routeName, extra: tx);
      ref.invalidate(accountDetailProvider(widget.account));
      ref.invalidate(accountListProvider);
    }
  }

  Future<void> _handleDuplicate(
    BuildContext context,
    WidgetRef ref,
    AccountLedgerItem item,
  ) async {
    if (item.isSensitiveEvent) {
      final ok = await _confirmSensitive(
        context,
        '複製初始值或餘額校正會影響帳戶統計，目前不建議複製。'
        '是否仍要略過此操作？',
      );
      if (ok) return;
      return;
    }
    if (item.transaction?.isLoanRepayment == true ||
        item.isLoanRepaymentCandidate) {
      await _confirmSensitive(
        context,
        '還款群組包含本金與利息兩筆紀錄；本階段先不建議複製，'
        '請使用計劃頁的本期還款建立新還款。',
      );
      return;
    }
    final tx = item.transaction;
    if (tx == null) return;
    await ref.read(transactionLedgerProvider.notifier).duplicate(tx);
    ref.invalidate(accountDetailProvider(widget.account));
    ref.invalidate(accountListProvider);
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    AccountLedgerItem item,
  ) async {
    if (item.event != null) {
      final ok = await _confirmSensitive(
        context,
        '刪除此筆初始值/餘額校正會影響帳戶統計，是否確認刪除？',
      );
      if (!ok) return;
      await ref
          .read(accountDetailProvider(widget.account).notifier)
          .deleteEvent(item.event!.id);
      ref.invalidate(accountListProvider);
      return;
    }
    final tx = item.transaction;
    if (tx == null) return;
    if (tx.isLoanRepayment || item.isLoanRepaymentCandidate) {
      final ok = await _confirmSensitive(
        context,
        '此筆屬於同一組還款事件。刪除後會同步刪除同組本金還本與利息支出，'
        '並影響貸款本金餘額，是否確認？',
      );
      if (!ok) return;
      await ref
          .read(transactionLedgerProvider.notifier)
          .deleteLoanRepaymentCluster(tx);
    } else {
      await ref.read(transactionLedgerProvider.notifier).delete(tx.id);
    }
    ref.invalidate(accountDetailProvider(widget.account));
    ref.invalidate(accountListProvider);
  }

  Future<bool> _confirmSensitive(
    BuildContext context,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('請確認'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認'),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _AccountSummaryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _AccountSummaryHeaderDelegate({
    required this.minExtentValue,
    required this.maxExtentValue,
    required this.child,
  });

  final double minExtentValue;
  final double maxExtentValue;
  final Widget child;

  @override
  double get minExtent => minExtentValue;

  @override
  double get maxExtent => maxExtentValue;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      elevation: overlapsContent ? 2 : 0,
      color: Colors.transparent,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _AccountSummaryHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.minExtentValue != minExtentValue ||
        oldDelegate.maxExtentValue != maxExtentValue;
  }
}

class _BalanceHeader extends ConsumerWidget {
  const _BalanceHeader({required this.state});

  final AccountDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoan = state.account.type == AccountType.loan;
    final balanceLabel = isLoan ? '目前貸款剩餘本金' : '目前帳戶餘額';
    final balanceValue =
        isLoan ? state.outstandingLoanPrincipal : state.currentBalance;
    final supportsAvailableBalance =
        state.account.type == AccountType.debitCard ||
            state.account.type == AccountType.bank;
    final availableBalance = supportsAvailableBalance
        ? ref.watch(
            accountAvailableBalancePresentationProvider(state.account),
          )
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              balanceLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _money(balanceValue, state.account.currency),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${state.account.type.label}・'
              '${state.account.currency.displayLabel}'
              '${isLoan ? '・還本後會遞減' : ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (availableBalance != null)
              DebitCardAvailableBalancePanel(value: availableBalance),
          ],
        ),
      ),
    );
  }
}

class _CompactPeriodSummaryCard extends StatelessWidget {
  const _CompactPeriodSummaryCard({
    required this.summary,
    required this.currency,
  });

  final AccountFlowSummary summary;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Keep the full period title separate from the amount: a long
            // e-wallet currency/negative balance must not turn '2026年' into
            // an uninformative '20...' on narrow phones.
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  summary.label,
                  maxLines: 1,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _compactMoney(summary.net, currency),
                  maxLines: 1,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '+ ${_compactMoney(summary.inflow, currency)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.teal),
            ),
            Text(
              '- ${_compactMoney(summary.outflow, currency)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.deepOrange),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountLedgerTile extends StatefulWidget {
  const _AccountLedgerTile({
    super.key,
    required this.item,
    required this.currency,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final AccountLedgerItem item;
  final CurrencyCode currency;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  State<_AccountLedgerTile> createState() => _AccountLedgerTileState();
}

class _AccountLedgerTileState extends State<_AccountLedgerTile> {
  static const double _actionWidth = 216;
  double _dragOffset = 0;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final offset = _revealed ? -_actionWidth : _dragOffset;
    return Card(
      child: ClipRect(
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            SizedBox(
              height: 82,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    label: '編輯',
                    onTap: () => _run(widget.onEdit),
                  ),
                  _ActionButton(
                    icon: Icons.copy_outlined,
                    label: '複製',
                    onTap: () => _run(widget.onDuplicate),
                  ),
                  _ActionButton(
                    icon: Icons.delete_outline,
                    label: '刪除',
                    onTap: () => _run(widget.onDelete),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: Matrix4.translationValues(offset, 0, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _revealed ? _hide : null,
                onHorizontalDragUpdate: (details) => setState(
                  () => _dragOffset =
                      (_dragOffset + details.delta.dx).clamp(
                    -_actionWidth,
                    0.0,
                  ),
                ),
                onHorizontalDragEnd: (_) => setState(() {
                  _revealed = _dragOffset.abs() > _actionWidth * 0.35;
                  _dragOffset = 0;
                }),
                // B1: the swipe foreground must own the ListTile ink layer.
                // A ColoredBox between ListTile and Card's Material hides ink
                // and triggers Flutter's framework assertion on real ledger rows.
                child: Material(
                  color: Theme.of(context).cardColor,
                  child: _LedgerContent(
                    item: widget.item,
                    currency: widget.currency,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hide() => setState(() {
        _revealed = false;
        _dragOffset = 0;
      });

  void _run(VoidCallback action) {
    _hide();
    action();
  }
}

class _LedgerContent extends StatelessWidget {
  const _LedgerContent({required this.item, required this.currency});

  final AccountLedgerItem item;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final sign = item.amountForAccount >= 0 ? '+' : '';
    // Preserve the entire source/provenance and per-row balance, but avoid
    // making unbounded SHA/UUID text the default transaction-list surface.
    return ExpansionTile(
      key: PageStorageKey<String>('account-ledger-${item.id}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(item.occurredAt)),
      leading: Icon(item.amountForAccount >= 0
          ? Icons.arrow_downward : Icons.arrow_upward),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedAlignment: Alignment.centerLeft,
      children: [
        const Text('來源／稽核資訊', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SelectableText(item.subtitle),
        const SizedBox(height: 6),
        Text('該筆後餘額：${_money(item.runningBalance, currency)}'),
      ],
      trailing: Text(
        '$sign${_money(item.amountForAccount, currency)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: TextButton(
        onPressed: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon), Text(label)],
        ),
      ),
    );
  }
}

String _money(double value, CurrencyCode currency) {
  return '${NumberFormat('#,##0.##').format(value)} ${currency.code}';
}

String _compactMoney(double value, CurrencyCode currency) {
  return '${NumberFormat.compactCurrency(symbol: '', decimalDigits: 1).format(value).trim()} ${currency.code}';
}

String _compactNumber(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
