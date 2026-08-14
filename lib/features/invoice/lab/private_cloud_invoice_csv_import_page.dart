import 'package:flutter/material.dart';

import '../../account/account_record.dart';
import '../cloud_invoice_candidate.dart';
import 'private_cloud_invoice_csv_enrichment_service.dart';
import 'private_cloud_invoice_csv_import_service.dart';
import 'private_cloud_invoice_draft_promotion_page.dart';
import 'private_cloud_invoice_csv_reconciliation_preview.dart';
import 'private_cloud_invoice_csv_reconciliation_review.dart';
import 'private_cloud_invoice_csv_unmatched_draft_service.dart';
import 'private_cloud_invoice_csv_unmatched_review.dart';

class PrivateCloudInvoiceCsvImportPage extends StatefulWidget {
  PrivateCloudInvoiceCsvImportPage({
    super.key,
    PrivateCloudInvoiceCsvImportPort? service,
    PrivateCloudInvoiceCsvEnrichmentPort? enrichmentPort,
  }) : service = service ?? PrivateCloudInvoiceCsvImportService(),
       enrichmentPort =
           enrichmentPort ?? PrivateCloudInvoiceCsvEnrichmentService();

  static const pickFileKey = Key('private_csv_pick_file');
  static const reviewSummaryKey = Key('private_csv_review_summary');
  static const completeReviewKey = Key('private_csv_complete_review');

  static Key alreadyLinkedCardKey(String invoiceId) =>
      ValueKey<String>('private_csv_already_linked_$invoiceId');

  static Key alreadyLinkedReviewKey(String invoiceId) =>
      ValueKey<String>('private_csv_already_linked_review_$invoiceId');

  static Key alreadyLinkedRestoreKey(String invoiceId) =>
      ValueKey<String>('private_csv_already_linked_restore_$invoiceId');
  static const alreadyLinkedExpansionKey = Key(
    'private_csv_already_linked_expansion',
  );
  static const unmatchedOpenPromotionKey = Key(
    'private_csv_unmatched_open_promotion',
  );
  static const completedResultKey = Key('private_csv_review_completed');
  static const finalConfirmationKey = Key(
    'private_csv_enrichment_confirmation',
  );
  static const executeEnrichmentKey = Key('private_csv_execute_enrichment');
  static const enrichmentResultKey = Key('private_csv_enrichment_result');
  static const unmatchedSectionKey = Key('private_csv_unmatched_section');
  static const unmatchedSelectAllKey = Key('private_csv_unmatched_select_all');
  static const unmatchedClearKey = Key('private_csv_unmatched_clear');
  static const unmatchedDeferMissingKey = Key(
    'private_csv_unmatched_defer_missing',
  );
  static const unmatchedApplyAccountKey = Key(
    'private_csv_unmatched_apply_account',
  );
  static const unmatchedBottomAccountKey = Key(
    'private_csv_unmatched_bottom_account',
  );
  static const unmatchedApplyMissingBottomKey = Key(
    'private_csv_unmatched_apply_missing_bottom',
  );
  static const unmatchedOverwriteBottomKey = Key(
    'private_csv_unmatched_overwrite_bottom',
  );
  static const unmatchedConfirmationKey = Key(
    'private_csv_unmatched_confirmation',
  );
  static const unmatchedCreateDraftsKey = Key(
    'private_csv_unmatched_create_drafts',
  );
  static const unmatchedResultKey = Key('private_csv_unmatched_result');

  final PrivateCloudInvoiceCsvImportPort service;
  final PrivateCloudInvoiceCsvEnrichmentPort enrichmentPort;

  @override
  State<PrivateCloudInvoiceCsvImportPage> createState() => _State();
}

class _State extends State<PrivateCloudInvoiceCsvImportPage> {
  final GlobalKey _sourceSummaryAnchor = GlobalKey();
  final GlobalKey _completedReviewAnchor = GlobalKey();
  final GlobalKey _unmatchedSectionAnchor = GlobalKey();
  final GlobalKey _enrichmentResultAnchor = GlobalKey();
  final GlobalKey _unmatchedResultAnchor = GlobalKey();

  PrivateCloudInvoiceCsvSource? source;
  PrivateCloudInvoiceCsvReconciliationReview? review;
  PrivateCloudInvoiceCsvUnmatchedReview? unmatchedReview;
  PrivateCloudInvoiceCsvEnrichmentSummary? enrichmentSummary;
  PrivateCloudInvoiceCsvUnmatchedDraftSummary? unmatchedDraftSummary;
  List<AccountRecord> accounts = const <AccountRecord>[];
  String? bulkAccountId;
  bool busy = false;
  bool reviewCompleted = false;
  bool finalConfirmation = false;
  bool unmatchedConfirmation = false;
  bool executing = false;
  bool importingUnmatched = false;
  String? error;

  bool get locked => busy || executing || importingUnmatched;

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

  Future<void> _pick() async {
    setState(() {
      busy = true;
      error = null;
      source = null;
      review = null;
      unmatchedReview = null;
      enrichmentSummary = null;
      unmatchedDraftSummary = null;
      accounts = const <AccountRecord>[];
      bulkAccountId = null;
      reviewCompleted = false;
      finalConfirmation = false;
      unmatchedConfirmation = false;
    });
    try {
      final result = await widget.service.pickAndPreview();
      if (!mounted || result == null) {
        return;
      }
      final preview = await widget.service.buildReconciliationPreview(
        result.preview,
      );
      final activeAccounts = await widget.service.listActiveAccounts();
      if (!mounted) {
        return;
      }
      setState(() {
        source = result;
        review = PrivateCloudInvoiceCsvReconciliationReview.fromPreview(
          preview,
        );
        unmatchedReview = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(
          preview,
        );
        accounts = activeAccounts;
      });
      _focusAfterFrame(_sourceSummaryAnchor);
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'CSV 對帳預覽失敗：$exception');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void _selectExisting({
    required String invoiceId,
    required String transactionId,
  }) {
    setState(() {
      review = review!.selectExisting(
        invoiceId: invoiceId,
        transactionId: transactionId,
      );
      _resetCompletion();
    });
  }

  void _beginAlreadyLinkedReview(String invoiceId) {
    setState(() {
      review = review!.beginAlreadyLinkedReview(invoiceId);
      _resetCompletion();
    });
  }

  void _restoreAlreadyLinkedSkip(String invoiceId) {
    setState(() {
      review = review!.restoreAlreadyLinkedSkip(invoiceId);
      _resetCompletion();
    });
  }

  void _keepSeparate(String invoiceId) {
    setState(() {
      review = review!.keepSeparate(invoiceId);
      _resetCompletion();
    });
  }

  void _clearDecision(String invoiceId) {
    setState(() {
      review = review!.clearMatchDecision(invoiceId);
      _resetCompletion();
    });
  }

  void _resetCompletion() {
    reviewCompleted = false;
    finalConfirmation = false;
    unmatchedConfirmation = false;
    enrichmentSummary = null;
    unmatchedDraftSummary = null;
  }

  void _completeReview() {
    final current = review;
    if (current == null || !current.allMatchRowsReviewed) {
      return;
    }
    setState(() {
      reviewCompleted = true;
      finalConfirmation = false;
      unmatchedConfirmation = false;
      enrichmentSummary = null;
      unmatchedDraftSummary = null;
    });
    _focusAfterFrame(_completedReviewAnchor);
  }

  Future<void> _executeEnrichment() async {
    final current = review;
    if (current == null ||
        !reviewCompleted ||
        !finalConfirmation ||
        locked ||
        current.summary.selectedExistingCount == 0) {
      return;
    }

    setState(() {
      executing = true;
      error = null;
      enrichmentSummary = null;
    });
    try {
      final result = await widget.enrichmentPort.executeConfirmed(
        review: current,
        finalConfirmation: finalConfirmation,
      );
      if (mounted) {
        setState(() => enrichmentSummary = result);
        _focusAfterFrame(_enrichmentResultAnchor);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = '發票資訊補充失敗：$exception');
      }
    } finally {
      if (mounted) {
        setState(() => executing = false);
      }
    }
  }

  void _toggleUnmatched(String invoiceId) {
    setState(() {
      unmatchedReview = unmatchedReview!.toggle(invoiceId);
      unmatchedConfirmation = false;
      unmatchedDraftSummary = null;
    });
  }

  void _selectAllUnmatched() {
    setState(() {
      unmatchedReview = unmatchedReview!.selectAll();
      unmatchedConfirmation = false;
      unmatchedDraftSummary = null;
    });
    _focusAfterFrame(_unmatchedSectionAnchor);
  }

  void _clearUnmatchedSelection() {
    setState(() {
      unmatchedReview = unmatchedReview!.clearSelection();
      unmatchedConfirmation = false;
      unmatchedDraftSummary = null;
    });
    _focusAfterFrame(_unmatchedSectionAnchor);
  }

  void _deferUnassignedUnmatched() {
    final current = unmatchedReview;
    if (current == null || !current.canDeferMissingAccounts) {
      return;
    }
    setState(() {
      unmatchedReview = current.deferSelectedWithoutAccount();
      unmatchedConfirmation = false;
      unmatchedDraftSummary = null;
    });
    _focusAfterFrame(_unmatchedSectionAnchor);
  }

  void _assignBulkAccount() {
    final accountId = bulkAccountId;
    final current = unmatchedReview;
    if (accountId == null || current == null || current.selectedCount == 0) {
      return;
    }
    setState(() {
      unmatchedReview = current.assignSelected(accountId);
      unmatchedConfirmation = false;
      unmatchedDraftSummary = null;
    });
    _focusAfterFrame(_unmatchedSectionAnchor);
  }

  void _assignBulkAccountToMissing() {
    final accountId = bulkAccountId;
    final current = unmatchedReview;
    if (accountId == null ||
        current == null ||
        current.selectedCount == 0 ||
        current.missingAccountCount == 0) {
      return;
    }
    setState(() {
      unmatchedReview = current.assignSelectedMissing(accountId);
      unmatchedConfirmation = false;
      unmatchedDraftSummary = null;
    });
    _focusAfterFrame(_unmatchedSectionAnchor);
  }

  void _assignUnmatchedAccount(String invoiceId, String? accountId) {
    setState(() {
      unmatchedReview = unmatchedReview!.assignInvoice(
        invoiceId: invoiceId,
        accountId: accountId,
      );
      unmatchedConfirmation = false;
      unmatchedDraftSummary = null;
    });
  }

  Future<void> _createUnmatchedDrafts() async {
    final currentSource = source;
    final currentReview = unmatchedReview;
    if (currentSource == null ||
        currentReview == null ||
        !reviewCompleted ||
        !unmatchedConfirmation ||
        !currentReview.canSubmit ||
        locked) {
      return;
    }

    setState(() {
      importingUnmatched = true;
      error = null;
      unmatchedDraftSummary = null;
    });
    try {
      final result =
          await PrivateCloudInvoiceCsvUnmatchedDraftService(
            importPort: widget.service,
          ).execute(
            preview: currentSource.preview,
            review: currentReview,
            accounts: accounts,
            confirmed: unmatchedConfirmation,
          );
      if (mounted) {
        setState(() => unmatchedDraftSummary = result);
      }
      if (!result.transactionCountUnchanged) {
        if (mounted) {
          setState(() {
            error = '草稿階段偵測到正式交易筆數異動，已停止自動導向，請人工覆核。';
          });
          _focusAfterFrame(_unmatchedResultAnchor);
        }
        return;
      }
      if (mounted && result.pendingDraftIds.isNotEmpty) {
        await _openPromotion(result.pendingDraftIds);
        if (mounted) {
          _focusAfterFrame(_unmatchedResultAnchor);
        }
      } else if (mounted) {
        _focusAfterFrame(_unmatchedResultAnchor);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = '未比對發票草稿建立失敗：$exception');
      }
    } finally {
      if (mounted) {
        setState(() => importingUnmatched = false);
      }
    }
  }

  Future<void> _openPromotion(Set<String> draftIds) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PrivateCloudInvoiceDraftPromotionPage(initialDraftIds: draftIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentReview = review;
    final currentUnmatched = unmatchedReview;
    return Scaffold(
      appBar: AppBar(title: const Text('財政部 CSV 對帳覆核 LAB')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '先以發票號碼辨識已存在且已連結的正式交易，這些項目預設略過；'
                  '其餘項目再依日期與總金額比對。未比對項目可批次指定帳戶，'
                  '所有補充與建立動作仍須明確覆核。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: PrivateCloudInvoiceCsvImportPage.pickFileKey,
              onPressed: locked ? null : _pick,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(busy ? '比對中' : '選擇財政部 CSV 並比對'),
            ),
            if (source != null && currentReview != null) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _sourceSummaryAnchor,
                child: _SourceSummaryCard(
                  source: source!,
                  preview: currentReview.preview,
                ),
              ),
              const SizedBox(height: 12),
              _ReviewSummaryCard(review: currentReview),
              const SizedBox(height: 12),
              if (currentReview.preview.alreadyLinkedCount > 0) ...[
                Card(
                  key: PrivateCloudInvoiceCsvImportPage
                      .alreadyLinkedExpansionKey,
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    title: Text(
                      '已存在且已連結（${currentReview.preview.alreadyLinkedCount}）',
                    ),
                    subtitle: const Text('已預設略過，需要時再展開逐筆覆核'),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      for (final item in currentReview.preview.items)
                        if (item.isAlreadyLinked) ...[
                          _ReconciliationItemCard(
                            item: item,
                            decision: currentReview.decisionFor(
                              item.invoice.id,
                            ),
                            enabled: !locked,
                            onSelectExisting: (transactionId) =>
                                _selectExisting(
                                  invoiceId: item.invoice.id,
                                  transactionId: transactionId,
                                ),
                            onBeginAlreadyLinkedReview: () =>
                                _beginAlreadyLinkedReview(item.invoice.id),
                            onRestoreAlreadyLinkedSkip: () =>
                                _restoreAlreadyLinkedSkip(item.invoice.id),
                            onKeepSeparate: () =>
                                _keepSeparate(item.invoice.id),
                            onClearDecision: () =>
                                _clearDecision(item.invoice.id),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              for (final item in currentReview.preview.items)
                if (!item.isAlreadyLinked &&
                    item.status !=
                        PrivateCloudInvoiceCsvReconciliationStatus
                            .unmatched) ...[
                  _ReconciliationItemCard(
                    item: item,
                    decision: currentReview.decisionFor(item.invoice.id),
                    enabled: !locked,
                    onSelectExisting: (transactionId) => _selectExisting(
                      invoiceId: item.invoice.id,
                      transactionId: transactionId,
                    ),
                    onBeginAlreadyLinkedReview: () =>
                        _beginAlreadyLinkedReview(item.invoice.id),
                    onRestoreAlreadyLinkedSkip: () =>
                        _restoreAlreadyLinkedSkip(item.invoice.id),
                    onKeepSeparate: () => _keepSeparate(item.invoice.id),
                    onClearDecision: () => _clearDecision(item.invoice.id),
                  ),
                  const SizedBox(height: 10),
                ],
              FilledButton.icon(
                key: PrivateCloudInvoiceCsvImportPage.completeReviewKey,
                onPressed: currentReview.allMatchRowsReviewed && !locked
                    ? _completeReview
                    : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('完成本次覆核'),
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
            if (reviewCompleted && currentReview != null) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _completedReviewAnchor,
                child: _CompletedReviewCard(review: currentReview),
              ),
              if (currentReview.summary.selectedExistingCount > 0) ...[
                CheckboxListTile(
                  key: PrivateCloudInvoiceCsvImportPage.finalConfirmationKey,
                  value: finalConfirmation,
                  onChanged: locked
                      ? null
                      : (value) => setState(() {
                          finalConfirmation = value ?? false;
                          enrichmentSummary = null;
                        }),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('我確認將發票資訊補充到選定的既有交易'),
                  subtitle: const Text('只新增發票號碼、賣方、稅額與消費明細 metadata；不修改原交易欄位。'),
                ),
                FilledButton.icon(
                  key: PrivateCloudInvoiceCsvImportPage.executeEnrichmentKey,
                  onPressed: finalConfirmation && !locked
                      ? _executeEnrichment
                      : null,
                  icon: const Icon(Icons.link_outlined),
                  label: Text(
                    executing
                        ? '補充中'
                        : '補充 ${currentReview.summary.selectedExistingCount} 筆既有交易',
                  ),
                ),
              ],
              if (currentUnmatched != null && currentUnmatched.hasItems) ...[
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: _unmatchedSectionAnchor,
                  child: _UnmatchedSection(
                    review: currentUnmatched,
                    accounts: accounts,
                    bulkAccountId: bulkAccountId,
                    enabled: !locked,
                    onBulkAccountChanged: (value) => setState(() {
                      bulkAccountId = value;
                    }),
                    onSelectAll: _selectAllUnmatched,
                    onClearSelection: _clearUnmatchedSelection,
                    onDeferMissingAccounts: _deferUnassignedUnmatched,
                    onApplyBulkAccount: _assignBulkAccount,
                    onApplyBulkAccountToMissing: _assignBulkAccountToMissing,
                    onToggle: _toggleUnmatched,
                    onAccountChanged: _assignUnmatchedAccount,
                  ),
                ),
                CheckboxListTile(
                  key:
                      PrivateCloudInvoiceCsvImportPage.unmatchedConfirmationKey,
                  value: unmatchedConfirmation,
                  onChanged: locked || !currentUnmatched.canSubmit
                      ? null
                      : (value) => setState(() {
                          unmatchedConfirmation = value ?? false;
                          unmatchedDraftSummary = null;
                        }),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('我確認為本次已完成歸戶的發票建立非正式草稿'),
                  subtitle: Text(
                    currentUnmatched.missingAccountCount > 0
                        ? currentUnmatched.assignedSelectedCount > 0
                              ? '已完成歸戶 ${currentUnmatched.assignedSelectedCount} 筆；'
                                    '請先暫緩 ${currentUnmatched.missingAccountCount} 筆未指定帳戶的發票。'
                              : '尚無已完成歸戶的選取發票。'
                        : '本次建立 ${currentUnmatched.selectedCount} 筆；'
                              '其餘 ${currentUnmatched.deferredCount} 筆暫緩。',
                  ),
                ),
                FilledButton.icon(
                  key:
                      PrivateCloudInvoiceCsvImportPage.unmatchedCreateDraftsKey,
                  onPressed:
                      unmatchedConfirmation &&
                          currentUnmatched.canSubmit &&
                          !locked
                      ? _createUnmatchedDrafts
                      : null,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(
                    importingUnmatched
                        ? '建立草稿中'
                        : '建立 ${currentUnmatched.selectedCount} 筆非正式草稿',
                  ),
                ),
              ],
            ],
            if (enrichmentSummary != null) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _enrichmentResultAnchor,
                child: _EnrichmentResultCard(summary: enrichmentSummary!),
              ),
            ],
            if (unmatchedDraftSummary != null) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _unmatchedResultAnchor,
                child: _UnmatchedDraftResultCard(
                  summary: unmatchedDraftSummary!,
                  onOpenPromotion:
                      unmatchedDraftSummary!.pendingDraftIds.isEmpty
                      ? null
                      : () => _openPromotion(
                          unmatchedDraftSummary!.pendingDraftIds,
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceSummaryCard extends StatelessWidget {
  const _SourceSummaryCard({required this.source, required this.preview});

  final PrivateCloudInvoiceCsvSource source;
  final PrivateCloudInvoiceCsvReconciliationPreview preview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.fileName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('明細列：${source.preview.detailRowCount}'),
            Text('發票群組：${source.preview.invoiceCount}'),
            Text('已存在且已連結：${preview.alreadyLinkedCount}'),
            Text('唯一比對：${preview.uniqueMatchCount}'),
            Text('多筆候選：${preview.ambiguousMatchCount}'),
            Text('未比對：${preview.unmatchedCount}'),
            Text('阻擋：${preview.blockedCount}'),
          ],
        ),
      ),
    );
  }
}

class _ReviewSummaryCard extends StatelessWidget {
  const _ReviewSummaryCard({required this.review});

  final PrivateCloudInvoiceCsvReconciliationReview review;

  @override
  Widget build(BuildContext context) {
    final summary = review.summary;
    return Card(
      key: PrivateCloudInvoiceCsvImportPage.reviewSummaryKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('覆核進度', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('已連結並預設略過：${summary.alreadyLinkedSkippedCount}'),
            Text('選定既有交易：${summary.selectedExistingCount}'),
            Text('保持分開：${summary.keepSeparateCount}'),
            Text('尚待確認的比對：${summary.unresolvedMatchCount}'),
            Text('待選帳戶：${summary.deferredAccountCount}'),
            Text('阻擋：${summary.blockedCount}'),
          ],
        ),
      ),
    );
  }
}

class _CompletedReviewCard extends StatelessWidget {
  const _CompletedReviewCard({required this.review});

  final PrivateCloudInvoiceCsvReconciliationReview review;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: PrivateCloudInvoiceCsvImportPage.completedResultKey,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '覆核已完成。\n'
          '已連結並略過：${review.summary.alreadyLinkedSkippedCount}\n'
          '選定既有交易：${review.summary.selectedExistingCount}\n'
          '保持分開：${review.summary.keepSeparateCount}\n'
          '待選帳戶：${review.summary.deferredAccountCount}\n'
          '阻擋：${review.summary.blockedCount}',
        ),
      ),
    );
  }
}

class _EnrichmentResultCard extends StatelessWidget {
  const _EnrichmentResultCard({required this.summary});

  final PrivateCloudInvoiceCsvEnrichmentSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: PrivateCloudInvoiceCsvImportPage.enrichmentResultKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '發票資訊補充結果',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('成功：${summary.committedCount}'),
            Text('重複 replay：${summary.replayCount}'),
            Text('交易已變更／衝突：${summary.conflictCount}'),
            Text('拒絕／失敗：${summary.rejectedCount}'),
            const Text('原交易核心欄位未修改。'),
          ],
        ),
      ),
    );
  }
}

class _UnmatchedSection extends StatelessWidget {
  const _UnmatchedSection({
    required this.review,
    required this.accounts,
    required this.bulkAccountId,
    required this.enabled,
    required this.onBulkAccountChanged,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onDeferMissingAccounts,
    required this.onApplyBulkAccount,
    required this.onApplyBulkAccountToMissing,
    required this.onToggle,
    required this.onAccountChanged,
  });

  final PrivateCloudInvoiceCsvUnmatchedReview review;
  final List<AccountRecord> accounts;
  final String? bulkAccountId;
  final bool enabled;
  final ValueChanged<String?> onBulkAccountChanged;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onDeferMissingAccounts;
  final VoidCallback onApplyBulkAccount;
  final VoidCallback onApplyBulkAccountToMissing;
  final ValueChanged<String> onToggle;
  final void Function(String invoiceId, String? accountId) onAccountChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: PrivateCloudInvoiceCsvImportPage.unmatchedSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '未比對發票：批次選帳戶',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '共 ${review.items.length} 筆；已選 ${review.selectedCount} 筆；'
              '已指定帳戶 ${review.assignedSelectedCount} 筆；'
              '未指定帳戶 ${review.missingAccountCount} 筆；'
              '暫緩／未選 ${review.deferredCount} 筆。',
            ),
            if (review.missingAccountCount > 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '可先暫緩未指定帳戶的發票，本次只建立已完成歸戶者。'
                  '暫緩項目不建立草稿；日後可重新匯入同一期間 CSV 再處理。',
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: PrivateCloudInvoiceCsvImportPage.unmatchedSelectAllKey,
                  onPressed: enabled ? onSelectAll : null,
                  child: const Text('全選'),
                ),
                OutlinedButton(
                  key: PrivateCloudInvoiceCsvImportPage.unmatchedClearKey,
                  onPressed: enabled ? onClearSelection : null,
                  child: const Text('清除選取'),
                ),
                if (review.canDeferMissingAccounts)
                  OutlinedButton.icon(
                    key: PrivateCloudInvoiceCsvImportPage
                        .unmatchedDeferMissingKey,
                    onPressed: enabled ? onDeferMissingAccounts : null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: Text('暫緩 ${review.missingAccountCount} 筆未指定帳戶'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: bulkAccountId,
              isExpanded: true,
              hint: const Text('批次指定支出帳戶'),
              items: _accountItems(accounts),
              onChanged: enabled ? onBulkAccountChanged : null,
            ),
            FilledButton.tonalIcon(
              key: PrivateCloudInvoiceCsvImportPage.unmatchedApplyAccountKey,
              onPressed:
                  enabled && review.selectedCount > 0 && bulkAccountId != null
                  ? onApplyBulkAccount
                  : null,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('套用帳戶到選取發票（覆蓋全部）'),
            ),
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('目前沒有可用帳戶，請先建立帳戶。'),
              ),
            const Divider(height: 24),
            for (final item in review.items)
              _UnmatchedInvoiceCard(
                item: item,
                selected: review.isSelected(item.invoice.id),
                accountId: review.accountIdFor(item.invoice.id),
                accounts: accounts,
                enabled: enabled,
                onToggle: () => onToggle(item.invoice.id),
                onAccountChanged: (accountId) =>
                    onAccountChanged(item.invoice.id, accountId),
              ),
            const Divider(height: 32),
            const Text(
              '清單底部快速套用帳戶',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '已選 ${review.selectedCount} 筆；'
              '已指定 ${review.assignedSelectedCount} 筆；'
              '未指定 ${review.missingAccountCount} 筆。',
            ),
            Text('目前選擇：${_accountDisplayLabel(accounts, bulkAccountId)}'),
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: PrivateCloudInvoiceCsvImportPage.unmatchedBottomAccountKey,
              value: bulkAccountId,
              isExpanded: true,
              hint: const Text('在此選擇要套用的支出帳戶'),
              items: _accountItems(accounts),
              onChanged: enabled ? onBulkAccountChanged : null,
            ),
            FilledButton.tonalIcon(
              key: PrivateCloudInvoiceCsvImportPage
                  .unmatchedApplyMissingBottomKey,
              onPressed:
                  enabled &&
                      review.selectedCount > 0 &&
                      review.missingAccountCount > 0 &&
                      bulkAccountId != null
                  ? onApplyBulkAccountToMissing
                  : null,
              icon: const Icon(Icons.playlist_add_check),
              label: Text('套用到 ${review.missingAccountCount} 筆未指定帳戶'),
            ),
            OutlinedButton.icon(
              key: PrivateCloudInvoiceCsvImportPage.unmatchedOverwriteBottomKey,
              onPressed:
                  enabled && review.selectedCount > 0 && bulkAccountId != null
                  ? onApplyBulkAccount
                  : null,
              icon: const Icon(Icons.warning_amber_outlined),
              label: Text('覆蓋全部 ${review.selectedCount} 筆已選帳戶'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '預設只補尚未指定帳戶的發票，不會覆蓋逐筆選擇。'
                '明確按下覆蓋按鈕時，才會改寫全部已選發票。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnmatchedInvoiceCard extends StatelessWidget {
  const _UnmatchedInvoiceCard({
    required this.item,
    required this.selected,
    required this.accountId,
    required this.accounts,
    required this.enabled,
    required this.onToggle,
    required this.onAccountChanged,
  });

  final PrivateCloudInvoiceCsvReconciliationItem item;
  final bool selected;
  final String? accountId;
  final List<AccountRecord> accounts;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<String?> onAccountChanged;

  @override
  Widget build(BuildContext context) {
    final candidate = item.invoice.candidate!;
    final summary = _lineItemSummary(candidate.lineItems);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: selected,
              onChanged: enabled ? (_) => onToggle() : null,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                candidate.displaySellerName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_date(candidate.invoiceDate)}｜NT\$ ${candidate.totalAmount.toStringAsFixed(0)}\n'
                '發票：${candidate.invoiceNumber}',
              ),
            ),
            Text('品項摘要：$summary'),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: accountId,
              isExpanded: true,
              hint: const Text('選擇支出帳戶'),
              items: _accountItems(accounts),
              onChanged: enabled ? onAccountChanged : null,
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text('查看完整品項（${candidate.lineItems.length}）'),
              children: [
                if (candidate.lineItems.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('CSV 未提供品項明細'),
                  )
                else
                  for (final lineItem in candidate.lineItems)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(lineItem.name),
                      subtitle: Text(_quantityText(lineItem)),
                      trailing: Text(
                        'NT\$ ${lineItem.amount.toStringAsFixed(0)}',
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnmatchedDraftResultCard extends StatelessWidget {
  const _UnmatchedDraftResultCard({
    required this.summary,
    required this.onOpenPromotion,
  });

  final PrivateCloudInvoiceCsvUnmatchedDraftSummary summary;
  final VoidCallback? onOpenPromotion;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: PrivateCloudInvoiceCsvImportPage.unmatchedResultKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '未比對發票草稿結果',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('新增草稿：${summary.committedCount}'),
            Text('既有待審草稿：${summary.replayCount}'),
            Text('拒絕／失敗：${summary.rejectedCount}'),
            Text(
              summary.transactionCountUnchanged
                  ? '正式交易筆數：未變更'
                  : '警告：正式交易筆數發生變化',
            ),
            if (summary.failedResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '未完成項目',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              for (final result in summary.failedResults)
                Text(
                  '${summary.invoiceNumberFor(result)}：'
                  '${result.status.name}｜${result.message}',
                ),
            ],
            if (onOpenPromotion != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: PrivateCloudInvoiceCsvImportPage.unmatchedOpenPromotionKey,
                onPressed: onOpenPromotion,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text('開啟 ${summary.pendingDraftIds.length} 筆草稿轉正式覆核'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReconciliationItemCard extends StatelessWidget {
  const _ReconciliationItemCard({
    required this.item,
    required this.decision,
    required this.enabled,
    required this.onSelectExisting,
    required this.onBeginAlreadyLinkedReview,
    required this.onRestoreAlreadyLinkedSkip,
    required this.onKeepSeparate,
    required this.onClearDecision,
  });

  final PrivateCloudInvoiceCsvReconciliationItem item;
  final PrivateCloudInvoiceCsvReviewDecision? decision;
  final bool enabled;
  final ValueChanged<String> onSelectExisting;
  final VoidCallback onBeginAlreadyLinkedReview;
  final VoidCallback onRestoreAlreadyLinkedSkip;
  final VoidCallback onKeepSeparate;
  final VoidCallback onClearDecision;

  @override
  Widget build(BuildContext context) {
    final candidate = item.invoice.candidate;
    final title = candidate?.invoiceNumber ?? item.invoice.id;
    final seller = candidate?.displaySellerName ?? '不可匯入';
    final amount = candidate?.totalAmount.toStringAsFixed(0) ?? '-';

    return Card(
      key: item.isAlreadyLinked
          ? PrivateCloudInvoiceCsvImportPage.alreadyLinkedCardKey(
              item.invoice.id,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('$seller｜$amount'),
            const SizedBox(height: 8),
            ..._statusContent(),
          ],
        ),
      ),
    );
  }

  List<Widget> _statusContent() {
    if (item.isAlreadyLinked) {
      return _alreadyLinkedContent();
    }
    switch (item.status) {
      case PrivateCloudInvoiceCsvReconciliationStatus.blocked:
        return const [Text('此發票群組被格式或狀態規則阻擋，不能進入覆核。')];
      case PrivateCloudInvoiceCsvReconciliationStatus.unmatched:
        return const <Widget>[];
      case PrivateCloudInvoiceCsvReconciliationStatus.uniqueExistingMatch:
      case PrivateCloudInvoiceCsvReconciliationStatus.ambiguousExistingMatch:
        final selectedTransactionId =
            decision?.action ==
                PrivateCloudInvoiceCsvReviewAction.enrichExisting
            ? decision?.transactionId
            : null;
        final keepSeparateSelected =
            decision?.action == PrivateCloudInvoiceCsvReviewAction.keepSeparate;
        return [
          Text(
            item.status ==
                    PrivateCloudInvoiceCsvReconciliationStatus
                        .uniqueExistingMatch
                ? '找到 1 筆同日期、同金額交易，請明確確認。'
                : '找到 ${item.matches.length} 筆同日期、同金額交易，請選擇正確項目。',
          ),
          for (final match in item.matches)
            _ReviewChoiceTile(
              selected: selectedTransactionId == match.transactionId,
              title: match.merchantName,
              subtitle:
                  '${match.accountName}｜${_dateTime(match.occurredAt)}｜'
                  '${match.amount.toStringAsFixed(0)}',
              onTap: enabled
                  ? () => onSelectExisting(match.transactionId)
                  : null,
            ),
          _ReviewChoiceTile(
            selected: keepSeparateSelected,
            title: '保持分開／稍後處理',
            onTap: enabled ? onKeepSeparate : null,
          ),
          if (decision != null)
            TextButton.icon(
              onPressed: enabled ? onClearDecision : null,
              icon: const Icon(Icons.undo),
              label: const Text('清除本筆決定'),
            ),
        ];
    }
  }

  List<Widget> _alreadyLinkedContent() {
    final linked = item.linkedTransaction;
    if (linked == null) {
      return const <Widget>[Text('已連結資料不完整，已阻擋自動處理，請人工確認。')];
    }

    final skipped =
        decision?.action ==
        PrivateCloudInvoiceCsvReviewAction.skipAlreadyLinked;
    final selectedTransactionId =
        decision?.action == PrivateCloudInvoiceCsvReviewAction.enrichExisting
        ? decision?.transactionId
        : null;
    final linkedSummary =
        '${linked.accountName}｜${_dateTime(linked.occurredAt)}｜'
        '${linked.amount.toStringAsFixed(0)}';

    return <Widget>[
      const Text(
        privateCloudInvoiceCsvAlreadyLinkedLabel,
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text('既有交易：${linked.merchantName}'),
      Text(linkedSummary),
      const SizedBox(height: 8),
      if (skipped) ...<Widget>[
        const Text('本筆不進入草稿、metadata 補充或批次帳戶流程。'),
        TextButton.icon(
          key: PrivateCloudInvoiceCsvImportPage.alreadyLinkedReviewKey(
            item.invoice.id,
          ),
          onPressed: enabled ? onBeginAlreadyLinkedReview : null,
          icon: const Icon(Icons.manage_search_outlined),
          label: const Text('重新覆核此筆'),
        ),
      ] else ...<Widget>[
        const Text('人工重新覆核中；只有明確選擇既有交易才會進入資料補充。'),
        _ReviewChoiceTile(
          selected: selectedTransactionId == linked.transactionId,
          title: linked.merchantName,
          subtitle: linkedSummary,
          onTap: enabled ? () => onSelectExisting(linked.transactionId) : null,
        ),
        TextButton.icon(
          key: PrivateCloudInvoiceCsvImportPage.alreadyLinkedRestoreKey(
            item.invoice.id,
          ),
          onPressed: enabled ? onRestoreAlreadyLinkedSkip : null,
          icon: const Icon(Icons.restore_outlined),
          label: const Text('恢復預設略過'),
        ),
      ],
    ];
  }
}

class _ReviewChoiceTile extends StatelessWidget {
  const _ReviewChoiceTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      enabled: onTap != null,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
    );
  }
}

String _accountDisplayLabel(List<AccountRecord> accounts, String? accountId) {
  if (accountId == null) return '尚未選擇帳戶';
  for (final account in accounts) {
    if (account.id == accountId) {
      return '${account.displayName}｜${account.type.label}｜${account.currency.code}';
    }
  }
  return '帳戶已不可用，請重新選擇';
}

List<DropdownMenuItem<String>> _accountItems(List<AccountRecord> accounts) {
  return accounts
      .map(
        (account) => DropdownMenuItem<String>(
          value: account.id,
          child: Text(
            '${account.displayName}｜${account.type.label}｜${account.currency.code}',
          ),
        ),
      )
      .toList(growable: false);
}

String _date(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _dateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${_date(value)} $hour:$minute';
}

String _lineItemSummary(List<CloudInvoiceLineItem> items) {
  if (items.isEmpty) {
    return '未提供品項';
  }
  final names = items.take(3).map((item) => item.name).join('、');
  if (items.length <= 3) {
    return names;
  }
  return '$names，另有 ${items.length - 3} 項';
}

String _quantityText(CloudInvoiceLineItem item) {
  final parts = <String>[];
  if (item.quantity != null) {
    parts.add('數量 ${item.quantity}');
  }
  if (item.unitPrice != null) {
    parts.add('單價 ${item.unitPrice!.toStringAsFixed(0)}');
  }
  return parts.isEmpty ? 'CSV 品項明細' : parts.join('｜');
}
