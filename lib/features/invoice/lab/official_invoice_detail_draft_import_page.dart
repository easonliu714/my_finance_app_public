import 'package:flutter/material.dart';

import '../../account/account_record.dart';
import 'official_invoice_detail_draft_import_service.dart';
import 'official_invoice_detail_draft_import_v2_service.dart';
import 'official_invoice_detail_enrichment.dart';
import 'private_cloud_invoice_draft_promotion_page.dart';

class OfficialInvoiceDetailDraftImportPage extends StatefulWidget {
  OfficialInvoiceDetailDraftImportPage({
    super.key,
    required this.batchResult,
    OfficialInvoiceDetailDraftImportV2Service? service,
  }) : service = service ?? OfficialInvoiceDetailDraftImportV2Service();

  static const Key accountKey = Key('official_detail_import_account');
  static const Key selectAllKey = Key('official_detail_import_select_all');
  static const Key clearKey = Key('official_detail_import_clear');
  static const Key confirmationKey = Key('official_detail_import_confirmation');
  static const Key stageKey = Key('official_detail_import_stage');
  static const Key resultKey = Key('official_detail_import_result');
  static const Key promotionKey = Key('official_detail_import_open_promotion');
  static const Key alreadyFormalExpansionKey =
      Key('official_detail_import_already_formal_expansion');

  static Key estimatedTaxConfirmationKey(String invoiceNumber) =>
      ValueKey<String>('official_detail_estimated_tax_$invoiceNumber');

  static Key deletedFormalNoticeKey(String invoiceNumber) =>
      ValueKey<String>('official_detail_deleted_formal_$invoiceNumber');

  final OfficialInvoiceDetailBatchResult batchResult;
  final OfficialInvoiceDetailDraftImportV2Service service;

  @override
  State<OfficialInvoiceDetailDraftImportPage> createState() => _State();
}

class _State extends State<OfficialInvoiceDetailDraftImportPage> {
  OfficialInvoiceDetailImportPreflightSnapshot? preflight;
  final Set<String> selectedInvoiceNumbers = <String>{};
  final Set<String> confirmedEstimatedTaxInvoiceNumbers = <String>{};
  String? selectedAccountId;
  bool loading = true;
  bool staging = false;
  bool confirmed = false;
  String? error;
  OfficialInvoiceDetailDraftImportSummary? summary;
  bool alreadyFormalExpanded = false;

  List<AccountRecord> get accounts =>
      preflight?.accounts ?? const <AccountRecord>[];

  List<OfficialInvoiceDetailImportPreflightItem> get selectableItems =>
      preflight?.selectableItems ??
      const <OfficialInvoiceDetailImportPreflightItem>[];

  AccountRecord? get selectedAccount {
    final accountId = selectedAccountId;
    if (accountId == null) return null;
    for (final account in accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  bool get allSelectedEstimatesConfirmed {
    for (final item in selectableItems) {
      if (!selectedInvoiceNumbers.contains(item.invoiceNumber)) continue;
      if (item.requiresEstimatedTaxConfirmation &&
          !confirmedEstimatedTaxInvoiceNumbers.contains(item.invoiceNumber)) {
        return false;
      }
    }
    return true;
  }

  bool get canStage =>
      !loading &&
      !staging &&
      confirmed &&
      selectedInvoiceNumbers.isNotEmpty &&
      allSelectedEstimatesConfirmed;

  @override
  void initState() {
    super.initState();
    _loadPreflight();
  }

  Future<void> _loadPreflight() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.service.loadPreflight(widget.batchResult);
      if (!mounted) return;
      setState(() {
        preflight = loaded;
        selectedInvoiceNumbers
          ..clear()
          ..addAll(loaded.selectableItems.map((item) => item.invoiceNumber));
        confirmedEstimatedTaxInvoiceNumbers.clear();
        if (selectedAccountId != null &&
            !loaded.accounts.any((item) => item.id == selectedAccountId)) {
          selectedAccountId = null;
        }
        confirmed = false;
        summary = null;
      });
    } catch (exception) {
      if (mounted) {
        setState(() => error = '正式交易預先比對失敗：$exception');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _resetReview() {
    confirmed = false;
    summary = null;
  }

  void _toggle(String invoiceNumber) {
    setState(() {
      if (!selectedInvoiceNumbers.add(invoiceNumber)) {
        selectedInvoiceNumbers.remove(invoiceNumber);
        confirmedEstimatedTaxInvoiceNumbers.remove(invoiceNumber);
      }
      _resetReview();
    });
  }

  void _setEstimatedTaxConfirmation(String invoiceNumber, bool value) {
    setState(() {
      if (value) {
        confirmedEstimatedTaxInvoiceNumbers.add(invoiceNumber);
      } else {
        confirmedEstimatedTaxInvoiceNumbers.remove(invoiceNumber);
      }
      _resetReview();
    });
  }

  void _selectAll() {
    setState(() {
      selectedInvoiceNumbers
        ..clear()
        ..addAll(selectableItems.map((item) => item.invoiceNumber));
      _resetReview();
    });
  }

  void _clearSelection() {
    setState(() {
      selectedInvoiceNumbers.clear();
      confirmedEstimatedTaxInvoiceNumbers.clear();
      _resetReview();
    });
  }

  Future<void> _stageDrafts() async {
    final account = selectedAccount;
    if (!canStage) return;
    setState(() {
      staging = true;
      error = null;
      summary = null;
    });
    try {
      final result = await widget.service.stageDrafts(
        batchResult: widget.batchResult,
        invoiceNumbers: Set<String>.unmodifiable(selectedInvoiceNumbers),
        confirmedEstimatedTaxInvoiceNumbers: Set<String>.unmodifiable(
          confirmedEstimatedTaxInvoiceNumbers,
        ),
        account: account,
        finalConfirmation: confirmed,
      );
      if (!mounted) return;
      setState(() {
        summary = result;
        confirmed = false;
      });
      if (!result.transactionCountUnchanged) {
        setState(() {
          error = '草稿階段偵測到正式交易筆數異動，已停止自動導向，請人工覆核。';
        });
        return;
      }
      if (result.pendingDraftIds.isNotEmpty) {
        await _openPromotion(result.pendingDraftIds);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = '建立待覆核草稿失敗：$exception');
      }
    } finally {
      if (mounted) setState(() => staging = false);
    }
  }

  Future<void> _openPromotion(Set<String> draftIds) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateCloudInvoiceDraftPromotionPage(
          initialDraftIds: draftIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = preflight;
    return Scaffold(
      appBar: AppBar(title: const Text('導入正式交易')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '兩階段建立正式支出：先排除仍存在的正式交易',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '本頁以發票號碼、官方精確日期時間與目前交易資料進行比對。'
                      '完全相同且交易仍存在者列為「已是正式交易」；'
                      '若原正式交易已由使用者刪除，會明確標示並允許重新建立待覆核草稿。'
                      '其餘項目可先建立草稿，下一頁再覆核帳戶、分類、成員與標籤。',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot != null) ...[
              _buildPreflightSummary(snapshot),
              const SizedBox(height: 12),
              _buildAccountCard(),
              const SizedBox(height: 12),
              _buildSelectionHeader(snapshot),
              const SizedBox(height: 8),
              if (selectableItems.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('本次沒有尚可建立草稿的官方明細。'),
                  ),
                )
              else
                for (final item in selectableItems) ...[
                  _buildSelectableInvoiceCard(item),
                  const SizedBox(height: 8),
                ],
              if (snapshot.alreadyFormalItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Card(
                  child: ExpansionTile(
                    key: OfficialInvoiceDetailDraftImportPage
                        .alreadyFormalExpansionKey,
                    initiallyExpanded: false,
                    onExpansionChanged: (value) =>
                        setState(() => alreadyFormalExpanded = value),
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(
                      '已是正式交易（${snapshot.alreadyFormalItems.length} 筆）',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      alreadyFormalExpanded
                          ? '點擊收合；這些項目的正式交易仍存在，不需再次建立。'
                          : '已排除且不需操作；需要檢視時再展開。',
                    ),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      for (final item in snapshot.alreadyFormalItems) ...[
                        _buildStatusCard(
                          item,
                          icon: Icons.verified_outlined,
                          label: '已是正式交易',
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
              if (snapshot.conflictItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                _sectionTitle('發票身分衝突／需覆核'),
                for (final item in snapshot.conflictItems) ...[
                  _buildStatusCard(
                    item,
                    icon: Icons.warning_amber_outlined,
                    label: '發票號碼相同但精確時間或交易關聯不一致',
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              CheckboxListTile(
                key: OfficialInvoiceDetailDraftImportPage.confirmationKey,
                value: confirmed,
                onChanged: staging ||
                        selectedInvoiceNumbers.isEmpty ||
                        !allSelectedEstimatesConfirmed
                    ? null
                    : (value) => setState(() => confirmed = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '我確認將選取的 ${selectedInvoiceNumbers.length} 筆官方明細建立為待覆核草稿',
                ),
                subtitle: const Text(
                  '帳戶可維持「待定帳戶」進入下一階段；此步驟尚不建立正式交易。'
                  '原交易已刪除的項目只會移除失效關聯並重開既有草稿。'
                  '推算稅額只會在逐筆確認後作為輔助明細。',
                ),
              ),
              FilledButton.icon(
                key: OfficialInvoiceDetailDraftImportPage.stageKey,
                onPressed: canStage ? _stageDrafts : null,
                icon: const Icon(Icons.playlist_add_check_circle_outlined),
                label: Text(
                  staging
                      ? '建立草稿中'
                      : '建立 ${selectedInvoiceNumbers.length} 筆待覆核草稿並進入交易比對',
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
              _buildResultCard(summary!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreflightSummary(
    OfficialInvoiceDetailImportPreflightSnapshot snapshot,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '正式交易預先比對',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('可導入：${snapshot.selectableItems.length}'),
            Text('其中原交易已刪除、可重建：${snapshot.rebuildableDeletedItems.length}'),
            Text('已是正式交易：${snapshot.alreadyFormalItems.length}'),
            Text('身分衝突／需覆核：${snapshot.conflictItems.length}'),
            Text('內容驗證未通過：${snapshot.rejectedItems.length}'),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '預設交易帳戶（選填）',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: OfficialInvoiceDetailDraftImportPage.accountKey,
              initialValue: selectedAccountId ?? '',
              decoration: const InputDecoration(
                labelText: '選擇扣款／付款帳戶',
                helperText: '可選「待定帳戶」直接進入下一階段；另建正式交易前才需指定。',
              ),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('待定帳戶（下一階段再指定）'),
                ),
                ...accounts.map(
                  (account) => DropdownMenuItem<String>(
                    value: account.id,
                    child: Text(
                      '${account.displayName}｜${account.type.label}｜${account.currency.code}',
                    ),
                  ),
                ),
              ],
              onChanged: staging
                  ? null
                  : (value) => setState(() {
                        selectedAccountId =
                            value == null || value.isEmpty ? null : value;
                        _resetReview();
                      }),
            ),
            if (accounts.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('目前沒有可用帳戶；仍可先建立待覆核草稿，但建立新正式交易前需先新增帳戶。'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionHeader(
    OfficialInvoiceDetailImportPreflightSnapshot snapshot,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '可導入 ${selectableItems.length} 筆；已選 ${selectedInvoiceNumbers.length} 筆',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (snapshot.rebuildableDeletedItems.isNotEmpty)
              Text(
                '${snapshot.rebuildableDeletedItems.length} 筆原正式交易已刪除，'
                '需由使用者確認後才會重新開啟草稿。',
              ),
            if (snapshot.rejectedItems.isNotEmpty)
              Text('${snapshot.rejectedItems.length} 筆內容驗證未通過，已排除。'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: OfficialInvoiceDetailDraftImportPage.selectAllKey,
                  onPressed: staging ? null : _selectAll,
                  child: const Text('全選可導入項目'),
                ),
                OutlinedButton(
                  key: OfficialInvoiceDetailDraftImportPage.clearKey,
                  onPressed: staging ? null : _clearSelection,
                  child: const Text('清除選取'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectableInvoiceCard(
    OfficialInvoiceDetailImportPreflightItem item,
  ) {
    final enrichment = item.enrichment;
    final invoiceNumber = item.invoiceNumber;
    final selected = selectedInvoiceNumbers.contains(invoiceNumber);
    final estimatedTax = enrichment.positiveEstimatedTaxAmount;
    final estimateConfirmed =
        confirmedEstimatedTaxInvoiceNumbers.contains(invoiceNumber);
    return Card.outlined(
      child: Column(
        children: [
          if (item.isDeletedFormalRebuild)
            Container(
              key: OfficialInvoiceDetailDraftImportPage
                  .deletedFormalNoticeKey(invoiceNumber),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.restore_from_trash_outlined),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '原正式交易已刪除。勾選並確認後，系統只會移除失效關聯、重新開啟待覆核草稿；不會在本頁直接建立交易。',
                    ),
                  ),
                ],
              ),
            ),
          CheckboxListTile(
            value: selected,
            onChanged: staging ? null : (_) => _toggle(invoiceNumber),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              invoiceNumber,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${_formatDateTime(enrichment.exactTimestamp)}｜'
              '${enrichment.sellerName ?? '賣方未提供'}\n'
              '總額：${_formatAmount(enrichment.detailTotal, enrichment.currencyCode)}｜'
              '品項：${enrichment.lineItems.length}',
            ),
          ),
          if (estimatedTax != null) ...[
            const Divider(height: 1),
            CheckboxListTile(
              key: OfficialInvoiceDetailDraftImportPage
                  .estimatedTaxConfirmationKey(invoiceNumber),
              value: estimateConfirmed,
              onChanged: staging || !selected
                  ? null
                  : (value) => _setEstimatedTaxConfirmation(
                        invoiceNumber,
                        value ?? false,
                      ),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '確認推算稅額：${_formatAmount(estimatedTax, enrichment.currencyCode)}',
              ),
              subtitle: Text(
                '計算方式：官方總額 '
                '${_formatAmount(enrichment.detailTotal, enrichment.currencyCode)} '
                '－品項小計 '
                '${_formatAmount(enrichment.lineItemSubtotal, enrichment.currencyCode)}。'
                '此數值不是官方明示稅額，只作為交易內容輔助。',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    OfficialInvoiceDetailImportPreflightItem item, {
    required IconData icon,
    required String label,
  }) {
    final enrichment = item.enrichment;
    return Card.outlined(
      child: ListTile(
        leading: Icon(icon),
        title: Text(
          item.invoiceNumber,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_formatDateTime(enrichment.exactTimestamp)}｜'
          '${enrichment.sellerName ?? '賣方未提供'}\n$label',
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildResultCard(OfficialInvoiceDetailDraftImportSummary result) {
    return Card(
      key: OfficialInvoiceDetailDraftImportPage.resultKey,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '草稿建立結果',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('新建草稿：${result.stagedCount}'),
            Text('冪等重播：${result.replayCount}'),
            Text('已是正式交易：${result.alreadyFormalCount}'),
            Text('衝突／需覆核：${result.conflictCount}'),
            Text('拒絕／失敗：${result.rejectedCount}'),
            Text('正式交易筆數未變：${result.transactionCountUnchanged ? '是' : '否'}'),
            if (result.pendingDraftIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                key: OfficialInvoiceDetailDraftImportPage.promotionKey,
                onPressed: staging
                    ? null
                    : () => _openPromotion(result.pendingDraftIds),
                icon: const Icon(Icons.post_add_outlined),
                label: Text(
                  '進入正式支出覆核（${result.pendingDraftIds.length} 筆）',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '時間未提供';
  final normalized = value.isUtc ? value.toLocal() : value;
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${normalized.year}-${pad(normalized.month)}-${pad(normalized.day)} '
      '${pad(normalized.hour)}:${pad(normalized.minute)}:${pad(normalized.second)}';
}

String _formatAmount(double? value, String? currencyCode) {
  if (value == null) return '未提供';
  final amount = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
  final currency = currencyCode?.trim();
  return currency == null || currency.isEmpty ? amount : '$currency $amount';
}
