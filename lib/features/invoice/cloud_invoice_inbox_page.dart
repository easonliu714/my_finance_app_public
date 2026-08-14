import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../capture/capture_help_button.dart';
import 'lab/private_cloud_invoice_draft_promotion_page.dart';
import 'lab/private_cloud_invoice_draft_promotion_service.dart';
import 'lab/private_cloud_invoice_lab_config.dart';
import 'lab/private_cloud_invoice_lab_page.dart';
import 'lab/private_cloud_invoice_lab_webview_page.dart';

abstract class CloudInvoiceInboxPort {
  Future<List<PrivateCloudInvoiceDraftCandidate>> listPendingDrafts();
}

class ProductionCloudInvoiceInboxPort implements CloudInvoiceInboxPort {
  ProductionCloudInvoiceInboxPort({
    PrivateCloudInvoiceDraftPromotionService? promotionService,
  }) : _promotionService =
            promotionService ?? PrivateCloudInvoiceDraftPromotionService();

  final PrivateCloudInvoiceDraftPromotionService _promotionService;

  @override
  Future<List<PrivateCloudInvoiceDraftCandidate>> listPendingDrafts() {
    return _promotionService.listPendingDrafts();
  }
}

class CloudInvoiceInboxPage extends StatefulWidget {
  CloudInvoiceInboxPage({
    super.key,
    CloudInvoiceInboxPort? port,
    this.onManualEntry,
    this.onOpenDraftPromotion,
    this.onOpenWebView,
    this.onOpenLab,
  }) : port = port ?? ProductionCloudInvoiceInboxPort();

  static const summaryKey = Key('cloud_invoice_inbox_summary');
  static const refreshKey = Key('cloud_invoice_inbox_refresh');
  static const promotionKey = Key('cloud_invoice_inbox_open_promotion');
  static const manualEntryKey = Key('cloud_invoice_inbox_manual_entry');
  static const webViewKey = Key('cloud_invoice_inbox_open_webview');
  static const labKey = Key('cloud_invoice_inbox_open_lab');
  static const reviewHelpKey = Key('cloud_invoice_inbox_review_help');

  final CloudInvoiceInboxPort port;
  final VoidCallback? onManualEntry;
  final VoidCallback? onOpenDraftPromotion;
  final VoidCallback? onOpenWebView;
  final VoidCallback? onOpenLab;

  @override
  State<CloudInvoiceInboxPage> createState() => _CloudInvoiceInboxPageState();
}

class _CloudInvoiceInboxPageState extends State<CloudInvoiceInboxPage> {
  List<PrivateCloudInvoiceDraftCandidate> _pendingDrafts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drafts = await widget.port.listPendingDrafts();
      if (!mounted) return;
      setState(() => _pendingDrafts = drafts);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '雲端發票工作箱載入失敗：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDraftPromotion() async {
    if (widget.onOpenDraftPromotion != null) {
      widget.onOpenDraftPromotion!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateCloudInvoiceDraftPromotionPage(),
      ),
    );
    if (mounted) await _load();
  }

  void _openWebView() {
    if (widget.onOpenWebView != null) {
      widget.onOpenWebView!();
      return;
    }
    context.pushNamed(PrivateCloudInvoiceLabWebViewPage.routeName);
  }

  void _openLab() {
    if (widget.onOpenLab != null) {
      widget.onOpenLab!();
      return;
    }
    context.pushNamed(PrivateCloudInvoiceLabPage.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('雲端發票工作箱'),
        actions: [
          IconButton(
            key: CloudInvoiceInboxPage.refreshKey,
            tooltip: '重新整理',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summaryCard(context),
              const SizedBox(height: 12),
              _webViewCard(context),
              const SizedBox(height: 12),
              _pendingDraftCard(context),
              const SizedBox(height: 12),
              _reviewRuleCard(context),
              const SizedBox(height: 12),
              _fallbackCard(context),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    return Card(
      key: CloudInvoiceInboxPage.summaryKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '待處理發票',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else ...[
              Text('${_pendingDrafts.length} 筆等待覆核'),
              const Text('建立支出前會重新檢查重複資料。'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _webViewCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '官方發票一次性匯入',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            const Text('自行登入官方頁面並匯出查詢結果。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: CloudInvoiceInboxPage.webViewKey,
              onPressed: _openWebView,
              icon: const Icon(Icons.public_outlined),
              label: const Text('開啟官方發票匯入'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingDraftCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '待轉正式支出',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Text('讀取中…')
            else if (_pendingDrafts.isEmpty)
              const Text('目前沒有待處理的雲端發票。')
            else ...[
              Text('共有 ${_pendingDrafts.length} 筆等待確認。'),
              const SizedBox(height: 8),
              for (final draft in _pendingDrafts.take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    draft.sellerName.trim().isEmpty
                        ? '未提供商家'
                        : draft.sellerName,
                  ),
                  subtitle: Text(
                    '${_date(draft.invoiceDate)}｜${draft.currencyCode ?? '幣別待確認'} '
                    '${draft.amount.toStringAsFixed(0)}｜${draft.accountName}',
                  ),
                ),
              if (_pendingDrafts.length > 3)
                Text('另有 ${_pendingDrafts.length - 3} 筆待處理。'),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: CloudInvoiceInboxPage.promotionKey,
                onPressed: _openDraftPromotion,
                icon: const Icon(Icons.post_add_outlined),
                label: Text('覆核 ${_pendingDrafts.length} 筆發票'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reviewRuleCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '覆核規則',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const CaptureHelpButton(
                  key: CloudInvoiceInboxPage.reviewHelpKey,
                  dialogTitle: '雲端發票覆核說明',
                  sections: [
                    CaptureHelpSection(
                      title: '正式支出',
                      body: '工作箱不會自動建立正式交易、商家或帳戶。',
                    ),
                    CaptureHelpSection(
                      title: '確認流程',
                      body: '建立支出前需確認分類、帳戶與重複檢查結果。',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('建立支出前請先確認內容。'),
            if (PrivateCloudInvoiceLabConfig.enabled) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: CloudInvoiceInboxPage.labKey,
                onPressed: _openLab,
                icon: const Icon(Icons.science_outlined),
                label: const Text('開啟私有雲端發票 LAB'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fallbackCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '其他方式',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('沒有可用草稿時，可改用手動輸入。'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: CloudInvoiceInboxPage.manualEntryKey,
              onPressed: widget.onManualEntry,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('改用手動輸入'),
            ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
