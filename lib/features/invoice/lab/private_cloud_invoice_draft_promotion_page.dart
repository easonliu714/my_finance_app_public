import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_record.dart';
import '../../dashboard/dashboard_page.dart';
import '../../transaction/grouped_account_choice_sheet.dart';
import '../cloud_invoice_candidate.dart';
import 'private_cloud_invoice_conflict_candidate_selection_page.dart';
import 'private_cloud_invoice_conflict_review_page.dart';
import 'private_cloud_invoice_draft_promotion_service.dart';
import 'taiwan_bank_historical_fx_rate_service.dart';

class PrivateCloudInvoiceDraftPromotionPage extends StatefulWidget {
  PrivateCloudInvoiceDraftPromotionPage({
    super.key,
    PrivateCloudInvoiceDraftPromotionService? service,
    TaiwanBankHistoricalFxRateService? fxRateService,
    this.initialDraftIds = const <String>{},
  })  : service = service ?? PrivateCloudInvoiceDraftPromotionService(),
        fxRateService = fxRateService ?? TaiwanBankHistoricalFxRateService();

  static const loadKey = Key('private_draft_promotion_load');
  static const selectAllKey = Key('private_draft_promotion_select_all');
  static const clearKey = Key('private_draft_promotion_clear');
  static const applyDefaultsKey = Key('private_draft_promotion_apply_defaults');
  static const confirmationKey = Key('private_draft_promotion_confirmation');
  static const promoteKey = Key('private_draft_promotion_execute');
  static const resultKey = Key('private_draft_promotion_result');
  static const returnHomeKey =
      Key('private_draft_promotion_return_home');
  static const conflictReviewKey = Key(
    'private_draft_promotion_conflict_review',
  );
  static const ambiguousReviewKey = Key(
    'private_draft_promotion_ambiguous_review',
  );

  final PrivateCloudInvoiceDraftPromotionService service;
  final TaiwanBankHistoricalFxRateService fxRateService;
  final Set<String> initialDraftIds;

  @override
  State<PrivateCloudInvoiceDraftPromotionPage> createState() => _State();
}

class _State extends State<PrivateCloudInvoiceDraftPromotionPage> {
  static const _categories = <String>[
    '早餐',
    '午餐',
    '晚餐',
    '飲料水果',
    '捷運',
    '客運',
    '家居百貨',
    '電子數碼',
    '手續費',
    '電影',
    '全部',
  ];
  static const _members = <String>['自己', '家人', '同事'];
  static const _tags = <String>['日常', '工作', '家庭', '報銷', '旅遊'];

  List<PrivateCloudInvoiceDraftCandidate> drafts = const [];
  List<AccountRecord> accounts = const [];
  final Set<String> selectedDraftIds = <String>{};
  final Map<String, String> categoryByDraftId = <String, String>{};
  final Map<String, String> memberByDraftId = <String, String>{};
  final Map<String, String> tagByDraftId = <String, String>{};
  final Map<String, String?> accountByDraftId = <String, String?>{};
  final Map<String, String> exchangeRateTextByDraftId =
      <String, String>{};
  final Map<String, String> actualAccountAmountTextByDraftId =
      <String, String>{};
  final Map<String, HistoricalFxRateQuote> fxQuoteByDraftId =
      <String, HistoricalFxRateQuote>{};
  final Map<String, String> fxQuoteErrorByDraftId = <String, String>{};
  final Set<String> fxQuoteLoadingDraftIds = <String>{};
  final Map<String, int> fxQuoteAttemptByDraftId = <String, int>{};
  final Map<String, int> fxFieldRevisionByDraftId = <String, int>{};
  final Map<String, int> actualAmountFieldRevisionByDraftId = <String, int>{};
  final GlobalKey _resultAnchor = GlobalKey();

  String? bulkAccountId;
  String bulkCategory = '全部';
  String bulkMember = '自己';
  String bulkTag = '日常';
  bool confirmed = false;
  bool loading = true;
  bool promoting = false;
  bool initialSelectionApplied = false;
  String? error;
  PrivateCloudInvoiceDraftPromotionSummary? summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _focusAfterFrame(GlobalKey anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = anchor.currentContext;
      if (targetContext == null) return;
      FocusManager.instance.primaryFocus?.unfocus();
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool get allSelectedComplete =>
      selectedDraftIds.isNotEmpty &&
      selectedDraftIds.every(
        (id) =>
            (categoryByDraftId[id] ?? '').trim().isNotEmpty &&
            (memberByDraftId[id] ?? '').trim().isNotEmpty &&
            (tagByDraftId[id] ?? '').trim().isNotEmpty &&
            _hasValidExchangeRate(
              drafts.firstWhere((draft) => draft.id == id),
            ),
      );

  Map<String, String> get conflictTransactionByDraftId {
    final current = summary;
    if (current == null) return const {};
    return <String, String>{
      for (final result in current.results)
        if (result.status == PrivateCloudInvoiceDraftPromotionStatus.conflict &&
            result.transactionId != null)
          result.draftId: result.transactionId!,
    };
  }

  Map<String, List<String>> get ambiguousTransactionIdsByDraftId {
    final current = summary;
    if (current == null) return const {};
    return <String, List<String>>{
      for (final result in current.results)
        if (result.requiresCandidateSelection)
          result.draftId: result.candidateTransactionIds,
    };
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loadedAccounts = await widget.service.listActiveAccounts();
      final items = await widget.service.listPendingDrafts();
      if (!mounted) return;
      setState(() {
        accounts = loadedAccounts;
        drafts = items;
        selectedDraftIds.removeWhere((id) => !items.any((d) => d.id == id));
        if (!initialSelectionApplied) {
          final available = items.map((d) => d.id).toSet();
          final preselected = widget.initialDraftIds.intersection(available);
          selectedDraftIds.addAll(preselected);
          for (final id in preselected) {
            final draft = items.firstWhere((item) => item.id == id);
            accountByDraftId.putIfAbsent(
              id,
              () => draft.accountId.trim().isEmpty ? null : draft.accountId,
            );
            categoryByDraftId.putIfAbsent(id, () => _defaultCategoryFor(draft));
            memberByDraftId.putIfAbsent(id, () => bulkMember);
            tagByDraftId.putIfAbsent(id, () => bulkTag);
            _ensureExchangeRate(draft);
          }
          for (final draft in items) {
            _ensureExchangeRate(draft);
          }
          initialSelectionApplied = true;
        }
      });
      unawaited(_refreshFxQuotes(items));
    } catch (e) {
      if (mounted) setState(() => error = '草稿載入失敗：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _defaultCategoryFor(PrivateCloudInvoiceDraftCandidate draft) {
    final suggestion = draft.categorySuggestion;
    if (suggestion != null &&
        suggestion.canPrefill &&
        suggestion.category != null) {
      return suggestion.category!;
    }
    return bulkCategory;
  }

  void _reset() {
    confirmed = false;
    summary = null;
  }

  void _toggle(String id) {
    setState(() {
      if (!selectedDraftIds.add(id)) {
        selectedDraftIds.remove(id);
      } else {
        final draft = drafts.firstWhere((item) => item.id == id);
        accountByDraftId.putIfAbsent(
          id,
          () => draft.accountId.trim().isEmpty ? null : draft.accountId,
        );
        categoryByDraftId.putIfAbsent(id, () => _defaultCategoryFor(draft));
        memberByDraftId.putIfAbsent(id, () => bulkMember);
        tagByDraftId.putIfAbsent(id, () => bulkTag);
        _ensureExchangeRate(draft);
      }
      _reset();
    });
  }

  void _selectAll() {
    setState(() {
      selectedDraftIds
        ..clear()
        ..addAll(drafts.map((d) => d.id));
      for (final d in drafts) {
        accountByDraftId.putIfAbsent(
          d.id,
          () => d.accountId.trim().isEmpty ? null : d.accountId,
        );
        categoryByDraftId.putIfAbsent(d.id, () => _defaultCategoryFor(d));
        memberByDraftId.putIfAbsent(d.id, () => bulkMember);
        tagByDraftId.putIfAbsent(d.id, () => bulkTag);
        _ensureExchangeRate(d);
      }
      _reset();
    });
  }

  void _clearSelection() => setState(() {
    selectedDraftIds.clear();
    _reset();
  });

  void _applyDefaults() {
    final ids = selectedDraftIds.toList(growable: false);
    setState(() {
      for (final id in ids) {
        if (bulkAccountId != null) {
          accountByDraftId[id] = bulkAccountId;
          exchangeRateTextByDraftId[id] = '';
          actualAccountAmountTextByDraftId[id] = '';
          fxQuoteByDraftId.remove(id);
          fxQuoteErrorByDraftId.remove(id);
          fxFieldRevisionByDraftId[id] =
              (fxFieldRevisionByDraftId[id] ?? 0) + 1;
          actualAmountFieldRevisionByDraftId[id] =
              (actualAmountFieldRevisionByDraftId[id] ?? 0) + 1;
        }
        categoryByDraftId[id] = bulkCategory;
        memberByDraftId[id] = bulkMember;
        tagByDraftId[id] = bulkTag;
      }
      _reset();
    });
    for (final id in ids) {
      final draft = drafts.firstWhere((item) => item.id == id);
      unawaited(_refreshFxQuote(draft));
    }
  }

  Future<void> _promote() async {
    if (!confirmed || !allSelectedComplete || promoting) return;
    setState(() {
      promoting = true;
      error = null;
      summary = null;
    });
    try {
      final result = await widget.service.promoteMany(
        decisions: selectedDraftIds
            .map(
              (id) => PrivateCloudInvoiceDraftPromotionDecision(
                draftId: id,
                category: categoryByDraftId[id]!,
                memberName: memberByDraftId[id]!,
                tagName: tagByDraftId[id]!,
                accountId: accountByDraftId[id],
                exchangeRateToBase: _reviewedSourceRateToTwd(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                accountRateToBase: _reviewedAccountRateToTwd(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                exchangeRateSourceToAccount: _reviewedCrossRate(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                reviewedAccountAmount: _reviewedAccountAmount(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                fxSourceName: _fxSourceNameFor(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                fxSourceReference: _fxSourceReferenceFor(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                fxRequestedDate:
                    drafts.firstWhere((draft) => draft.id == id).invoiceDate,
                fxEffectiveDate: _fxEffectiveDateFor(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                fxEffectiveDateTime: _fxEffectiveDateTimeFor(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                fxSpotBuyToBase: _fxSpotBuyFor(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                fxSpotSellToBase: _fxSpotSellFor(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
                fxSelectionPolicy: _fxSelectionPolicyFor(
                  drafts.firstWhere((draft) => draft.id == id),
                ),
              ),
            )
            .toList(growable: false),
        finalConfirmation: confirmed,
      );
      if (!mounted) return;
      setState(() {
        summary = result;
        confirmed = false;
      });
      if (result.conflictCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('尚有 ${result.conflictCount} 筆衝突未完成，請點擊下方「立即逐筆確認」。'),
          ),
        );
      } else if (result.accountRequiredCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '尚有 ${result.accountRequiredCount} 筆沒有候選交易，請指定付款帳戶後再次送出。',
            ),
          ),
        );
      }
      await _load();
      _focusAfterFrame(_resultAnchor);
    } catch (e) {
      if (mounted) setState(() => error = '草稿轉正式支出失敗：$e');
    } finally {
      if (mounted) setState(() => promoting = false);
    }
  }

  Future<void> _openConflictReview() async {
    final conflicts = conflictTransactionByDraftId;
    if (conflicts.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateCloudInvoiceConflictReviewPage(
          conflictTransactionByDraftId: conflicts,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => summary = null);
    await _load();
  }

  Future<void> _openAmbiguousReview() async {
    final ambiguous = ambiguousTransactionIdsByDraftId;
    if (ambiguous.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateCloudInvoiceConflictCandidateSelectionPage(
          candidateTransactionIdsByDraftId: ambiguous,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => summary = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('雲端發票草稿轉正式支出')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '只列出尚未轉正式支出的發票草稿。系統會先跨帳戶檢查同日期、同金額交易；'
                  '找到候選時沿用既有交易帳戶；只有另建新交易才需指定付款帳戶。分類智慧建議可由使用者修改。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: PrivateCloudInvoiceDraftPromotionPage.loadKey,
              onPressed: loading || promoting ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重新載入草稿'),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (drafts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('目前沒有待轉正式支出的雲端發票草稿。'),
                ),
              )
            else ...[
              _bulkControls(),
              const SizedBox(height: 12),
              for (final draft in drafts) ...[
                _draftCard(draft),
                const SizedBox(height: 10),
              ],
              CheckboxListTile(
                key: PrivateCloudInvoiceDraftPromotionPage.confirmationKey,
                value: confirmed,
                onChanged: promoting || !allSelectedComplete
                    ? null
                    : (v) => setState(() => confirmed = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('我確認先比對既有交易，並將資料完整者建立為正式支出'),
                subtitle: const Text('帳戶可先留空進行比對；無候選且要另建新交易時才必須指定。'),
              ),
              FilledButton.icon(
                key: PrivateCloudInvoiceDraftPromotionPage.promoteKey,
                onPressed: confirmed && allSelectedComplete && !promoting
                    ? _promote
                    : null,
                icon: const Icon(Icons.post_add_outlined),
                label: Text(
                  promoting ? '比對／建立中' : '比對並處理 ${selectedDraftIds.length} 筆',
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!),
                ),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: 12),
              KeyedSubtree(key: _resultAnchor, child: _resultCard(summary!)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultCard(PrivateCloudInvoiceDraftPromotionSummary result) {
    final conflicts = conflictTransactionByDraftId;
    final ambiguous = ambiguousTransactionIdsByDraftId;
    final pendingCount =
        conflicts.length + ambiguous.length + result.accountRequiredCount;
    final hasPendingReview = pendingCount > 0;
    return Card(
      key: PrivateCloudInvoiceDraftPromotionPage.resultKey,
      color: hasPendingReview
          ? Theme.of(context).colorScheme.tertiaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasPendingReview ? '需要下一步操作' : '草稿轉正式支出結果',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '成功：${result.committedCount}\n'
              '重複 replay：${result.replayCount}\n'
              '可能重複／衝突：${result.conflictCount}\n'
              '待指定帳戶：${result.accountRequiredCount}\n'
              '拒絕／失敗：${result.rejectedCount}',
            ),
            if (hasPendingReview) ...[
              const SizedBox(height: 12),
              Text(
                '尚有 $pendingCount 筆尚未完成。重複候選需逐筆確認；沒有候選的新交易請回到上方指定帳戶後再送出。',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (ambiguous.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: PrivateCloudInvoiceDraftPromotionPage.ambiguousReviewKey,
                  onPressed: promoting ? null : _openAmbiguousReview,
                  icon: const Icon(Icons.touch_app_outlined),
                  label: Text('立即選擇候選交易（${ambiguous.length} 筆）'),
                ),
              ),
            ],
            if (!hasPendingReview &&
                result.rejectedCount == 0 &&
                result.committedCount + result.replayCount > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: PrivateCloudInvoiceDraftPromotionPage.returnHomeKey,
                  onPressed: () =>
                      context.goNamed(DashboardPage.routeName),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('完成並回到首頁'),
                ),
              ),
            ],
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: PrivateCloudInvoiceDraftPromotionPage.conflictReviewKey,
                  onPressed: promoting ? null : _openConflictReview,
                  icon: const Icon(Icons.touch_app_outlined),
                  label: Text('立即逐筆確認衝突（${conflicts.length} 筆）'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bulkControls() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '待處理 ${drafts.length} 筆；已選 ${selectedDraftIds.length} 筆',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: PrivateCloudInvoiceDraftPromotionPage.selectAllKey,
                onPressed: promoting ? null : _selectAll,
                child: const Text('全選'),
              ),
              OutlinedButton(
                key: PrivateCloudInvoiceDraftPromotionPage.clearKey,
                onPressed: promoting ? null : _clearSelection,
                child: const Text('清除選取'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _bulkAccountDropdown(),
          _bulkDropdown(
            '批次分類',
            bulkCategory,
            _categories,
            (v) => bulkCategory = v,
          ),
          _bulkDropdown('批次成員', bulkMember, _members, (v) => bulkMember = v),
          _bulkDropdown('批次標籤', bulkTag, _tags, (v) => bulkTag = v),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: PrivateCloudInvoiceDraftPromotionPage.applyDefaultsKey,
            onPressed: promoting || selectedDraftIds.isEmpty
                ? null
                : _applyDefaults,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('套用到選取草稿'),
          ),
        ],
      ),
    ),
  );

  Widget _bulkAccountDropdown() => _groupedAccountField(
        key: const Key('private_draft_promotion_bulk_account'),
        label: '批次付款帳戶（選填）',
        helperText: '只套用於另建新交易；連結既有交易時沿用既有帳戶。',
        accountId: bulkAccountId,
        onSelected: (account) => setState(() {
          bulkAccountId = account.id;
          _reset();
        }),
        onClear: () => setState(() {
          bulkAccountId = null;
          _reset();
        }),
      );

  Widget _bulkDropdown(
    String label,
    String current,
    List<String> values,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: current,
    decoration: InputDecoration(labelText: label),
    items: values
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(growable: false),
    onChanged: promoting
        ? null
        : (v) {
            if (v == null) {
              return;
            }
            setState(() {
              onChanged(v);
              _reset();
            });
          },
  );

  Widget _draftCard(PrivateCloudInvoiceDraftCandidate draft) {
    final selected = selectedDraftIds.contains(draft.id);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: selected,
              onChanged: promoting ? null : (_) => _toggle(draft.id),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                draft.sellerName.isEmpty ? '未提供商家' : draft.sellerName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${_date(draft.invoiceDate)}｜${_formatDraftAmount(draft)}\n'
                '${_fxSummaryText(draft)}\n'
                '發票：${draft.invoiceNumber}｜帳戶：'
                '${draft.accountName.trim().isEmpty ? '尚未指定' : draft.accountName}',
              ),
            ),
            Text('品項摘要：${_lineItemSummary(draft.lineItems)}'),
            if (draft.categorySuggestion?.category != null) ...[
              const SizedBox(height: 6),
              Text(
                '智慧建議：${draft.categorySuggestion!.category} '
                '（${(draft.categorySuggestion!.confidence * 100).round()}%）',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(draft.categorySuggestion!.reasons.join('；')),
            ],
            if (selected) ...[
              const SizedBox(height: 8),
              _accountReviewDropdown(draft),
              if (_draftCurrency(draft) != _targetCurrency(draft))
                _exchangeRateField(draft),
              _reviewDropdown(
                draft.id,
                '支出分類',
                categoryByDraftId[draft.id],
                _categories,
                (v) => categoryByDraftId[draft.id] = v,
              ),
              _reviewDropdown(
                draft.id,
                '成員',
                memberByDraftId[draft.id],
                _members,
                (v) => memberByDraftId[draft.id] = v,
              ),
              _reviewDropdown(
                draft.id,
                '標籤',
                tagByDraftId[draft.id],
                _tags,
                (v) => tagByDraftId[draft.id] = v,
              ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('查看完整品項（${draft.lineItems.length}）'),
              children: draft.lineItems.isEmpty
                  ? const [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('草稿未提供品項明細'),
                      ),
                    ]
                  : draft.lineItems
                        .map(
                          (item) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.name),
                            subtitle: Text(_quantityText(item)),
                            trailing: Text(
                              '${_draftCurrency(draft).code} '                              '${item.amount.toStringAsFixed(_draftCurrency(draft).decimalDigits)}',
                            ),
                          ),
                        )
                        .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountReviewDropdown(PrivateCloudInvoiceDraftCandidate draft) =>
      _groupedAccountField(
        key: Key('private_draft_promotion_account_${draft.id}'),
        label: '付款帳戶（建立新交易時必填）',
        helperText: '選擇帳戶後會依發票交易日自動載入臺銀中價，並換算為帳戶幣別。',
        accountId: accountByDraftId[draft.id],
        onSelected: (account) {
          setState(() {
            accountByDraftId[draft.id] = account.id;
            exchangeRateTextByDraftId[draft.id] = '';
            actualAccountAmountTextByDraftId[draft.id] = '';
            fxQuoteByDraftId.remove(draft.id);
            fxQuoteErrorByDraftId.remove(draft.id);
            fxFieldRevisionByDraftId[draft.id] =
                (fxFieldRevisionByDraftId[draft.id] ?? 0) + 1;
            actualAmountFieldRevisionByDraftId[draft.id] =
                (actualAmountFieldRevisionByDraftId[draft.id] ?? 0) + 1;
            _reset();
          });
          unawaited(_refreshFxQuote(draft));
        },
        onClear: () {
          setState(() {
            accountByDraftId[draft.id] = null;
            exchangeRateTextByDraftId[draft.id] = '';
            actualAccountAmountTextByDraftId[draft.id] = '';
            fxQuoteByDraftId.remove(draft.id);
            fxQuoteErrorByDraftId.remove(draft.id);
            fxFieldRevisionByDraftId[draft.id] =
                (fxFieldRevisionByDraftId[draft.id] ?? 0) + 1;
            actualAmountFieldRevisionByDraftId[draft.id] =
                (actualAmountFieldRevisionByDraftId[draft.id] ?? 0) + 1;
            _reset();
          });
          unawaited(_refreshFxQuote(draft));
        },
      );

  Widget _groupedAccountField({
    required Key key,
    required String label,
    required String helperText,
    required String? accountId,
    required ValueChanged<AccountRecord> onSelected,
    required VoidCallback onClear,
  }) {
    final account = _accountById(accountId);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            key: key,
            onPressed: promoting
                ? null
                : () async {
                    final picked = await showGroupedAccountChoiceSheet(
                      context,
                      title: label,
                      accounts: accounts,
                      selectedDisplayName: account?.displayName ?? '',
                    );
                    if (picked != null && mounted) onSelected(picked);
                  },
            icon: Icon(_accountTypeIcon(account?.type)),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                account == null
                    ? '尚未指定'
                    : '${account.displayName}｜${account.type.label}・${account.currency.displayLabel}',
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: Text(helperText)),
              if (account != null)
                TextButton(
                  onPressed: promoting ? null : onClear,
                  child: const Text('清除'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exchangeRateField(PrivateCloudInvoiceDraftCandidate draft) {
    final sourceCurrency = _draftCurrency(draft);
    final accountCurrency = _targetCurrency(draft);
    final text = exchangeRateTextByDraftId[draft.id] ?? '';
    final parsed = double.tryParse(text);
    final actualText = actualAccountAmountTextByDraftId[draft.id] ?? '';
    final parsedActual = double.tryParse(actualText);
    final actualRate = _actualAccountAmountRate(draft);
    final reviewedRate = actualRate ?? parsed;
    final equivalent = parsedActual != null && parsedActual > 0
        ? accountCurrency.roundAmount(parsedActual)
        : reviewedRate == null || reviewedRate <= 0
            ? null
            : accountCurrency.roundAmount(draft.amount * reviewedRate);
    final quote = fxQuoteByDraftId[draft.id];
    final loadingQuote = fxQuoteLoadingDraftIds.contains(draft.id);
    final quoteError = fxQuoteErrorByDraftId[draft.id];
    final supportsActualAmount = sourceCurrency == CurrencyCode.twd ||
        accountCurrency == CurrencyCode.twd;
    final automaticHelper = loadingQuote
        ? '正在依 ${_date(draft.invoiceDate)} 載入臺銀即期買賣中價…'
        : quote != null
            ? '${quote.sourceName}｜採用 ${_date(quote.effectiveDate)}｜'
                '約 ${accountCurrency.code} '
                '${equivalent?.toStringAsFixed(accountCurrency.decimalDigits) ?? '--'}'
            : quoteError != null
                ? supportsActualAmount
                    ? '$quoteError；可改輸入帳戶實際扣帳金額，由系統反推匯率。'
                    : '$quoteError；非 TWD 對非 TWD 帳戶仍須取得雙邊牌告。'
                : '自動值僅為帳務參考，不等同卡片或銀行實際清算匯率。';
    final rateHelper = actualRate == null
        ? automaticHelper
        : '以實際扣帳金額反推：1 ${sourceCurrency.code} = '
            '${actualRate.toStringAsFixed(2)} ${accountCurrency.code}；'
            '正式交易將使用 ${accountCurrency.code} '
            '${equivalent!.toStringAsFixed(accountCurrency.decimalDigits)}。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: ValueKey<String>(
            '${draft.id}-fx-${fxFieldRevisionByDraftId[draft.id] ?? 0}',
          ),
          initialValue: text,
          enabled: !promoting && !loadingQuote,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText:
                '匯率（1 ${sourceCurrency.code} = ? ${accountCurrency.code}）',
            helperText: rateHelper,
            errorText: loadingQuote ||
                    quoteError != null ||
                    actualRate != null ||
                    (parsed != null && parsed > 0)
                ? null
                : '請輸入大於 0 的匯率，或輸入實際扣帳金額',
          ),
          onChanged: (value) => setState(() {
            exchangeRateTextByDraftId[draft.id] = value.trim();
            if ((actualAccountAmountTextByDraftId[draft.id] ?? '').isNotEmpty) {
              actualAccountAmountTextByDraftId[draft.id] = '';
              actualAmountFieldRevisionByDraftId[draft.id] =
                  (actualAmountFieldRevisionByDraftId[draft.id] ?? 0) + 1;
            }
            _reset();
          }),
        ),
        _fxStatusCard(
          draft,
          loadingQuote: loadingQuote,
          quote: quote,
          quoteError: quoteError,
        ),
        if (supportsActualAmount) ...[
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey<String>(
              '${draft.id}-actual-'
              '${actualAmountFieldRevisionByDraftId[draft.id] ?? 0}',
            ),
            initialValue: actualText,
            enabled: !promoting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '實際扣帳金額（${accountCurrency.code}）',
              helperText: actualRate == null
                  ? '例如帳戶實際扣款 ${accountCurrency.code} 74；'
                      '輸入後會優先使用此金額，並將反推匯率自動填入上方欄位至小數點後 2 位。'
                  : '已將反推匯率自動填入上方欄位，並以此金額作為正式交易金額；'
                      '原始發票 ${sourceCurrency.code} ${draft.amount} 仍會保留。',
              errorText: actualText.isNotEmpty &&
                      (parsedActual == null || parsedActual <= 0)
                  ? '實際扣帳金額必須大於 0'
                  : null,
            ),
            onChanged: (value) => setState(() {
              final trimmed = value.trim();
              actualAccountAmountTextByDraftId[draft.id] = trimmed;
              final actual = double.tryParse(trimmed);
              exchangeRateTextByDraftId[draft.id] =
                  actual != null && actual > 0 && draft.amount > 0
                      ? (actual / draft.amount).toStringAsFixed(2)
                      : '';
              fxFieldRevisionByDraftId[draft.id] =
                  (fxFieldRevisionByDraftId[draft.id] ?? 0) + 1;
              _reset();
            }),
          ),
        ],
        if (quoteError != null && !loadingQuote) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: promoting ? null : () => _retryFxQuote(draft),
              icon: const Icon(Icons.refresh),
              label: const Text('重新取得臺銀匯率'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _fxStatusCard(
    PrivateCloudInvoiceDraftCandidate draft, {
    required bool loadingQuote,
    required HistoricalFxRateQuote? quote,
    required String? quoteError,
  }) {
    final attempt = fxQuoteAttemptByDraftId[draft.id] ?? 0;
    final colors = Theme.of(context).colorScheme;
    final String title;
    final String message;
    final IconData icon;
    final Color background;
    if (loadingQuote) {
      title = '臺銀匯率查詢中（第 $attempt 次）';
      message = '正在重新連線並查詢 ${_date(draft.invoiceDate)} 的歷史即期中價。';
      icon = Icons.sync;
      background = colors.secondaryContainer;
    } else if (quote != null) {
      title = '臺銀匯率取得成功（第 $attempt 次）';
      final quotedAt = quote.effectiveQuoteDateTime;
      final buy = quote.sourceSpotBuyToTwd;
      final sell = quote.sourceSpotSellToTwd;
      final auditParts = <String>[
        quote.sourceName,
        if (quote.requestedDateTime != null)
          '發票時間 ${_dateTime(quote.requestedDateTime!)}',
        '採用牌告 ${quotedAt == null ? _date(quote.effectiveDate) : _dateTime(quotedAt)}',
        if (buy != null && sell != null)
          '即期買入 ${buy.toStringAsFixed(6)}／賣出 ${sell.toStringAsFixed(6)}',
        '1 ${quote.sourceCurrency.code} = '
            '${quote.sourceToAccountRate.toStringAsFixed(6)} '
            '${quote.accountCurrency.code}',
        if (quote.selectionPolicy != null)
          '選取規則 ${_selectionPolicyLabel(quote.selectionPolicy!)}',
      ];
      message = auditParts.join('｜');
      icon = Icons.check_circle_outline;
      background = colors.primaryContainer;
    } else if (quoteError != null) {
      title = '臺銀匯率取得失敗（第 $attempt 次）';
      message = quoteError;
      icon = Icons.error_outline;
      background = colors.errorContainer;
    } else {
      title = '臺銀匯率尚未查詢';
      message = '選擇付款帳戶後，系統會依發票交易日自動查詢。';
      icon = Icons.info_outline;
      background = colors.surfaceContainerHighest;
    }
    return Card(
      key: Key('private_draft_promotion_fx_status_${draft.id}'),
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loadingQuote)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryFxQuote(
    PrivateCloudInvoiceDraftCandidate draft,
  ) async {
    if (promoting || fxQuoteLoadingDraftIds.contains(draft.id)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    widget.fxRateService.clearCache();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('正在重新取得 ${_date(draft.invoiceDate)} 的臺銀匯率…'),
          duration: const Duration(seconds: 20),
        ),
      );
    await _refreshFxQuote(draft);
    if (!mounted) return;
    final quote = fxQuoteByDraftId[draft.id];
    final quoteError = fxQuoteErrorByDraftId[draft.id];
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            quote != null
                ? '臺銀匯率已更新：採用 '
                    '${quote.effectiveQuoteDateTime == null ? _date(quote.effectiveDate) : _dateTime(quote.effectiveQuoteDateTime!)}；'
                    '1 ${quote.sourceCurrency.code} = '
                    '${quote.sourceToAccountRate.toStringAsFixed(6)} '
                    '${quote.accountCurrency.code}'
                : '臺銀匯率重新查詢失敗：${quoteError ?? '未取得可用結果'}',
          ),
        ),
      );
  }

  void _ensureExchangeRate(PrivateCloudInvoiceDraftCandidate draft) {
    final sourceCurrency = _draftCurrency(draft);
    final accountCurrency = _targetCurrency(draft);
    exchangeRateTextByDraftId.putIfAbsent(
      draft.id,
      () => sourceCurrency == accountCurrency ? '1' : '',
    );
    actualAccountAmountTextByDraftId.putIfAbsent(draft.id, () => '');
  }

  Future<void> _refreshFxQuotes(
    List<PrivateCloudInvoiceDraftCandidate> items,
  ) async {
    for (final draft in items) {
      if (_draftCurrency(draft) != CurrencyCode.twd ||
          _targetCurrency(draft) != CurrencyCode.twd) {
        await _refreshFxQuote(draft);
      }
    }
  }

  Future<void> _refreshFxQuote(
    PrivateCloudInvoiceDraftCandidate draft,
  ) async {
    final sourceCurrency = _draftCurrency(draft);
    final accountCurrency = _targetCurrency(draft);
    if (sourceCurrency == CurrencyCode.twd &&
        accountCurrency == CurrencyCode.twd) {
      if (!mounted) return;
      setState(() {
        exchangeRateTextByDraftId[draft.id] = '1';
        fxQuoteByDraftId.remove(draft.id);
        fxQuoteErrorByDraftId.remove(draft.id);
        fxQuoteLoadingDraftIds.remove(draft.id);
        fxFieldRevisionByDraftId[draft.id] =
            (fxFieldRevisionByDraftId[draft.id] ?? 0) + 1;
        _reset();
      });
      return;
    }
    if (fxQuoteLoadingDraftIds.contains(draft.id)) return;
    if (mounted) {
      setState(() {
        fxQuoteLoadingDraftIds.add(draft.id);
        fxQuoteAttemptByDraftId[draft.id] =
            (fxQuoteAttemptByDraftId[draft.id] ?? 0) + 1;
        fxQuoteErrorByDraftId.remove(draft.id);
        _reset();
      });
    }
    try {
      final quote = await widget.fxRateService.quote(
        transactionDate: draft.invoiceDate,
        sourceCurrency: sourceCurrency,
        accountCurrency: accountCurrency,
      );
      if (!mounted || _targetCurrency(draft) != accountCurrency) return;
      setState(() {
        fxQuoteByDraftId[draft.id] = quote;
        exchangeRateTextByDraftId[draft.id] =
            quote.sourceToAccountRate.toStringAsPrecision(12);
        fxQuoteErrorByDraftId.remove(draft.id);
        fxFieldRevisionByDraftId[draft.id] =
            (fxFieldRevisionByDraftId[draft.id] ?? 0) + 1;
        _reset();
      });
    } on HistoricalFxRateException catch (error) {
      if (!mounted) return;
      setState(() {
        fxQuoteByDraftId.remove(draft.id);
        exchangeRateTextByDraftId[draft.id] = '';
        fxQuoteErrorByDraftId[draft.id] = error.userFacingMessage;
        fxFieldRevisionByDraftId[draft.id] =
            (fxFieldRevisionByDraftId[draft.id] ?? 0) + 1;
        _reset();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        fxQuoteByDraftId.remove(draft.id);
        exchangeRateTextByDraftId[draft.id] = '';
        fxQuoteErrorByDraftId[draft.id] = '自動匯率載入失敗：$error';
        fxFieldRevisionByDraftId[draft.id] =
            (fxFieldRevisionByDraftId[draft.id] ?? 0) + 1;
        _reset();
      });
    } finally {
      if (mounted) {
        setState(() => fxQuoteLoadingDraftIds.remove(draft.id));
      }
    }
  }

  CurrencyCode _targetCurrency(PrivateCloudInvoiceDraftCandidate draft) {
    final selectedId = accountByDraftId[draft.id];
    final account = _accountById(
      selectedId == null || selectedId.isEmpty ? draft.accountId : selectedId,
    );
    return account?.currency ?? CurrencyCode.twd;
  }

  bool _hasValidExchangeRate(PrivateCloudInvoiceDraftCandidate draft) {
    final source = _draftCurrency(draft);
    final target = _targetCurrency(draft);
    if (source == CurrencyCode.twd && target == CurrencyCode.twd) {
      return true;
    }
    final cross = _reviewedCrossRate(draft);
    final sourceToTwd = _reviewedSourceRateToTwd(draft);
    final accountToTwd = _reviewedAccountRateToTwd(draft);
    return cross != null &&
        cross.isFinite &&
        cross > 0 &&
        sourceToTwd != null &&
        sourceToTwd.isFinite &&
        sourceToTwd > 0 &&
        accountToTwd != null &&
        accountToTwd.isFinite &&
        accountToTwd > 0;
  }

  double? _reviewedCrossRate(PrivateCloudInvoiceDraftCandidate draft) {
    if (_draftCurrency(draft) == _targetCurrency(draft)) return 1;
    final actualRate = _actualAccountAmountRate(draft);
    if (actualRate != null) return actualRate;
    return double.tryParse(exchangeRateTextByDraftId[draft.id] ?? '');
  }

  double? _reviewedSourceRateToTwd(
    PrivateCloudInvoiceDraftCandidate draft,
  ) {
    final source = _draftCurrency(draft);
    final target = _targetCurrency(draft);
    if (source == CurrencyCode.twd) return 1;
    final actualRate = _actualAccountAmountRate(draft);
    if (actualRate != null && target == CurrencyCode.twd) return actualRate;
    final quote = fxQuoteByDraftId[draft.id];
    if (quote != null && quote.sourceCurrency == source) {
      return quote.sourceMidpointToTwd;
    }
    final cross = _reviewedCrossRate(draft);
    if (target == CurrencyCode.twd) return cross;
    final accountRate = _reviewedAccountRateToTwd(draft);
    if (cross == null || accountRate == null) return null;
    return cross * accountRate;
  }

  double? _reviewedAccountRateToTwd(
    PrivateCloudInvoiceDraftCandidate draft,
  ) {
    final target = _targetCurrency(draft);
    if (target == CurrencyCode.twd) return 1;
    final actualRate = _actualAccountAmountRate(draft);
    if (_draftCurrency(draft) == CurrencyCode.twd && actualRate != null) {
      return 1 / actualRate;
    }
    final quote = fxQuoteByDraftId[draft.id];
    if (quote != null && quote.accountCurrency == target) {
      return quote.accountMidpointToTwd;
    }
    if (_draftCurrency(draft) == CurrencyCode.twd) {
      final cross = _reviewedCrossRate(draft);
      return cross == null || cross <= 0 ? null : 1 / cross;
    }
    return null;
  }

  double? _actualAccountAmountValue(
    PrivateCloudInvoiceDraftCandidate draft,
  ) {
    final source = _draftCurrency(draft);
    final target = _targetCurrency(draft);
    if (source != CurrencyCode.twd && target != CurrencyCode.twd) return null;
    final value = double.tryParse(
      actualAccountAmountTextByDraftId[draft.id] ?? '',
    );
    return value == null || !value.isFinite || value <= 0 ? null : value;
  }

  double? _actualAccountAmountRate(
    PrivateCloudInvoiceDraftCandidate draft,
  ) {
    final actual = _actualAccountAmountValue(draft);
    if (actual == null || draft.amount <= 0) return null;
    return double.parse((actual / draft.amount).toStringAsFixed(2));
  }

  double? _reviewedAccountAmount(
    PrivateCloudInvoiceDraftCandidate draft,
  ) {
    final target = _targetCurrency(draft);
    final actual = _actualAccountAmountValue(draft);
    if (actual != null) return target.roundAmount(actual);
    final cross = _reviewedCrossRate(draft);
    if (cross == null || !cross.isFinite || cross <= 0) return null;
    return target.roundAmount(draft.amount * cross);
  }

  bool _usesActualAccountAmount(PrivateCloudInvoiceDraftCandidate draft) =>
      _actualAccountAmountValue(draft) != null;

  String _fxSourceNameFor(PrivateCloudInvoiceDraftCandidate draft) =>
      _usesActualAccountAmount(draft)
          ? '使用者輸入實際扣帳金額（反推）'
          : fxQuoteByDraftId[draft.id]?.sourceName ?? 'MANUAL_REVIEW';

  String? _fxSourceReferenceFor(PrivateCloudInvoiceDraftCandidate draft) =>
      _usesActualAccountAmount(draft)
          ? null
          : fxQuoteByDraftId[draft.id]?.sourceUrl;

  DateTime? _fxEffectiveDateFor(PrivateCloudInvoiceDraftCandidate draft) =>
      _usesActualAccountAmount(draft)
          ? null
          : fxQuoteByDraftId[draft.id]?.effectiveDate;

  DateTime? _fxEffectiveDateTimeFor(
    PrivateCloudInvoiceDraftCandidate draft,
  ) =>
      _usesActualAccountAmount(draft)
          ? null
          : fxQuoteByDraftId[draft.id]?.effectiveQuoteDateTime;

  double? _fxSpotBuyFor(PrivateCloudInvoiceDraftCandidate draft) =>
      _usesActualAccountAmount(draft)
          ? null
          : fxQuoteByDraftId[draft.id]?.sourceSpotBuyToTwd;

  double? _fxSpotSellFor(PrivateCloudInvoiceDraftCandidate draft) =>
      _usesActualAccountAmount(draft)
          ? null
          : fxQuoteByDraftId[draft.id]?.sourceSpotSellToTwd;

  String? _fxSelectionPolicyFor(
    PrivateCloudInvoiceDraftCandidate draft,
  ) =>
      _usesActualAccountAmount(draft)
          ? null
          : fxQuoteByDraftId[draft.id]?.selectionPolicy;

  String _fxSummaryText(PrivateCloudInvoiceDraftCandidate draft) {
    final source = _draftCurrency(draft);
    final target = _targetCurrency(draft);
    if (source == CurrencyCode.twd && target == CurrencyCode.twd) {
      return '帳戶幣別：${target.displayLabel}｜無需換匯';
    }
    final actual = _actualAccountAmountValue(draft);
    final actualRate = _actualAccountAmountRate(draft);
    if (actual != null && actualRate != null) {
      return '實際扣帳 ${target.code} '
          '${target.roundAmount(actual).toStringAsFixed(target.decimalDigits)}｜'
          '反推 1 ${source.code} = '
          '${actualRate.toStringAsFixed(2)} ${target.code}';
    }
    if (fxQuoteLoadingDraftIds.contains(draft.id)) {
      return '正在載入交易日臺銀即期買賣中價…';
    }
    final quote = fxQuoteByDraftId[draft.id];
    if (quote != null) {
      final converted = target.roundAmount(
        draft.amount * quote.sourceToAccountRate,
      );
      final quotedAt = quote.effectiveQuoteDateTime;
      return '臺銀 ${quotedAt == null ? _date(quote.effectiveDate) : _dateTime(quotedAt)} 即期中價｜'
          '1 ${source.code} = '
          '${quote.sourceToAccountRate.toStringAsPrecision(10)} ${target.code}｜'
          '約 ${target.code} ${converted.toStringAsFixed(target.decimalDigits)}';
    }
    final failure = fxQuoteErrorByDraftId[draft.id];
    return failure == null ? '尚未載入交易日匯率' : '匯率待人工覆核：$failure';
  }

  AccountRecord? _accountById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  Widget _reviewDropdown(
    String draftId,
    String label,
    String? current,
    List<String> values,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey<String>('$draftId-$label-${current ?? ''}'),
    initialValue: current,
    decoration: InputDecoration(labelText: label),
    items: values
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(growable: false),
    onChanged: promoting
        ? null
        : (v) {
            if (v == null) {
              return;
            }
            setState(() {
              onChanged(v);
              _reset();
            });
          },
  );
}

CurrencyCode _draftCurrency(PrivateCloudInvoiceDraftCandidate draft) =>
    currencyFromCode(draft.currencyCode);

String _formatDraftAmount(PrivateCloudInvoiceDraftCandidate draft) {
  final currency = _draftCurrency(draft);
  return '${currency.code} '
      '${draft.amount.toStringAsFixed(currency.decimalDigits)}';
}

IconData _accountTypeIcon(AccountType? type) {
  return switch (type) {
    AccountType.cash => Icons.payments_outlined,
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.debitCard || AccountType.creditCard =>
      Icons.credit_card_outlined,
    AccountType.storedValue => Icons.subway_outlined,
    AccountType.eWallet => Icons.account_balance_wallet_outlined,
    AccountType.investment => Icons.trending_up,
    AccountType.loan => Icons.request_quote_outlined,
    AccountType.other => Icons.more_horiz,
    null => Icons.account_balance_wallet_outlined,
  };
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _dateTime(DateTime value) =>
    '${_date(value)} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';

String _selectionPolicyLabel(String value) => switch (value) {
      'latest_at_or_before_transaction_time' => '交易時間以前最近牌告',
      'requested_date_last_quote_after_market' => '交易日晚於市場最後牌告',
      'requested_date_last_quote_no_time' => '無精確時間，採交易日最後牌告',
      'previous_business_day_last_quote' => '前一營業日最後牌告',
      'same_currency_identity' => '同幣別無需換匯',
      _ => value,
    };
String _lineItemSummary(List<CloudInvoiceLineItem> items) {
  if (items.isEmpty) {
    return '未提供品項';
  }
  final names = items.take(3).map((i) => i.name).join('、');
  return items.length <= 3 ? names : '$names，另有 ${items.length - 3} 項';
}

String _quantityText(CloudInvoiceLineItem item) {
  final parts = <String>[];
  if (item.quantity != null) {
    parts.add('數量 ${item.quantity}');
  }
  if (item.unitPrice != null) {
    parts.add('單價 ${item.unitPrice!.toStringAsFixed(0)}');
  }
  return parts.isEmpty ? '發票品項' : parts.join('｜');
}
