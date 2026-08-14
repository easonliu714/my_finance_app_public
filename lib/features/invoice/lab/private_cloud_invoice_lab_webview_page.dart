import 'dart:async';

import 'package:flutter/material.dart';

import 'authenticated_selector_probe_panel.dart';
import 'disposable_webview_session.dart';
import 'ephemeral_csv_download_result_page.dart';
import 'flutter_landing_webview_session_runtime.dart';
import 'official_invoice_detail_enrichment_sheet.dart';
import 'private_cloud_invoice_csv_import_service.dart';
import 'private_cloud_invoice_lab_config.dart';
import 'private_cloud_invoice_lab_lifecycle_policy.dart';

class PrivateCloudInvoiceLabWebViewPage extends StatefulWidget {
  const PrivateCloudInvoiceLabWebViewPage({super.key});

  static const String routeName = 'cloud-invoice-webview-import';
  static const String routePath = '/cloud-invoice/webview-import';

  static const Key consentKey = Key('ephemeral_webview_consent');
  static const Key startKey = Key('ephemeral_webview_start');
  static const Key probeKey = Key('ephemeral_webview_probe');
  static const Key officialDetailKey =
      Key('ephemeral_webview_official_detail');
  static const Key cancelKey = Key('ephemeral_webview_cancel');
  static const Key finishKey = Key('ephemeral_webview_finish');
  static const Key runtimeKey = Key('ephemeral_webview_runtime');

  @override
  State<PrivateCloudInvoiceLabWebViewPage> createState() =>
      _PrivateCloudInvoiceLabWebViewPageState();
}

class _PrivateCloudInvoiceLabWebViewPageState
    extends State<PrivateCloudInvoiceLabWebViewPage>
    with WidgetsBindingObserver {
  late final DisposableWebViewSessionController _controller;
  String? _downloadErrorCode;
  bool _handoffInProgress = false;
  bool _popAfterCleanup = false;
  bool _popCleanupInProgress = false;
  bool _officialDetailOpening = false;

  static const Duration _officialDetailOpenSettleDelay =
      Duration(milliseconds: 650);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = DisposableWebViewSessionController(
      runtimeFactory: () => FlutterLandingWebViewSessionRuntime(
        onCsvReady: _handleCsvReady,
        onDownloadError: _handleDownloadError,
      ),
    )..addListener(_onControllerChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final disposition =
        PrivateCloudInvoiceLabLifecyclePolicy.dispositionFor(state);
    if (disposition != PrivateCloudInvoiceLabLifecycleDisposition.cancel) {
      return;
    }
    if (_controller.phase == DisposableWebViewSessionPhase.active) {
      unawaited(_controller.cancel());
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});

    if (!_popAfterCleanup) return;
    if (_controller.phase == DisposableWebViewSessionPhase.active &&
        !_popCleanupInProgress) {
      unawaited(_cancelForSystemBack());
      return;
    }
    if (_controller.phase == DisposableWebViewSessionPhase.completed ||
        _controller.phase == DisposableWebViewSessionPhase.failed ||
        _controller.phase == DisposableWebViewSessionPhase.consent) {
      _popAfterCleanup = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  void _requestPopAfterCleanup() {
    if (_popAfterCleanup) return;
    _popAfterCleanup = true;

    if (_controller.phase == DisposableWebViewSessionPhase.active) {
      unawaited(_cancelForSystemBack());
    }
    // During `starting` or `cleaning`, the controller listener waits for the
    // next safe phase. A starting session is cancelled immediately after it
    // becomes active; an existing cleanup is allowed to finish exactly once.
  }

  Future<void> _cancelForSystemBack() async {
    if (_popCleanupInProgress ||
        _controller.phase != DisposableWebViewSessionPhase.active) {
      return;
    }
    _popCleanupInProgress = true;
    try {
      await _controller.cancel();
    } finally {
      _popCleanupInProgress = false;
    }
  }

  void _handleDownloadError(String errorCode) {
    if (!mounted) return;
    setState(() => _downloadErrorCode = errorCode);
  }

  Future<void> _handleCsvReady(PrivateCloudInvoiceCsvSource source) async {
    if (_handoffInProgress) return;
    _handoffInProgress = true;
    if (_controller.phase == DisposableWebViewSessionPhase.active) {
      await _controller.finish();
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EphemeralCsvDownloadResultPage(source: source),
      ),
    );
  }

  Future<void> _start() async {
    setState(() => _downloadErrorCode = null);
    await _controller.start(PrivateCloudInvoiceLabConfig.officialLandingUri);
  }

  Future<void> _finish() async {
    await _controller.finish();
  }

  Future<void> _cancel() async {
    await _controller.cancel();
  }

  Future<void> _openOfficialDetailEnrichment() async {
    if (_officialDetailOpening) return;
    setState(() => _officialDetailOpening = true);
    try {
      // Keep the WebView uncovered briefly so the official page can
      // finish its checkbox click/change handlers before DOM inspection.
      await Future<void>.delayed(_officialDetailOpenSettleDelay);
      if (!mounted ||
          _controller.phase != DisposableWebViewSessionPhase.active) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => OfficialInvoiceDetailEnrichmentSheet(
          controller: _controller,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('讀取官方勾選狀態失敗：$error')),
      );
    } finally {
      if (mounted) setState(() => _officialDetailOpening = false);
    }
  }

  void _openProbe() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登入後頁面相容性檢查'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: AuthenticatedSelectorProbePanel(controller: _controller),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _controller.phase;
    final mustCleanupBeforePop =
        phase == DisposableWebViewSessionPhase.starting ||
            phase == DisposableWebViewSessionPhase.active ||
            phase == DisposableWebViewSessionPhase.cleaning;

    return PopScope<Object?>(
      canPop: !mustCleanupBeforePop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && mustCleanupBeforePop) _requestPopAfterCleanup();
      },
      child: _buildPhase(phase),
    );
  }

  Widget _buildPhase(DisposableWebViewSessionPhase phase) {
    switch (phase) {
      case DisposableWebViewSessionPhase.consent:
        return _buildConsent();
      case DisposableWebViewSessionPhase.starting:
        return _buildProgress(
          title: '正在建立一次性登入工作階段',
          message: '正在清除前次 Cookie、快取、網站儲存空間與暫存檔。',
        );
      case DisposableWebViewSessionPhase.active:
        return _buildActive();
      case DisposableWebViewSessionPhase.cleaning:
        return _buildProgress(
          title: '正在清除登入工作階段',
          message: '正在取消傳輸並清除 Cookie、快取、網站儲存空間與頁面狀態。',
        );
      case DisposableWebViewSessionPhase.completed:
        return _buildCompleted();
      case DisposableWebViewSessionPhase.failed:
        return _buildFailure(canReset: true);
      case DisposableWebViewSessionPhase.blocked:
        return _buildFailure(canReset: false);
    }
  }

  Widget _buildConsent() {
    return Scaffold(
      appBar: AppBar(title: const Text('官方發票一次性匯入')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '一次性登入、查詢與 CSV 匯入',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            const Text(
              '您將在財政部官方頁面自行登入、查詢並點擊匯出。App 不填寫欄位、不隱藏點擊、不建立查詢，也不保存帳號、密碼或驗證碼。',
            ),
            const SizedBox(height: 12),
            const Text(
              '只有您主動點擊官方匯出控制項後，App 才會在前景使用目前工作階段 Cookie 執行一次下載。CSV 只進入私有暫存目錄，解析後立即刪除。',
            ),
            const SizedBox(height: 12),
            const Text(
              '短暫鎖定螢幕或切換 App 不視為取消；返回後會繼續目前記憶體中的剩餘佇列。若 Android 終止 App process，未完成批次才會中止。只有明確取消、離開此頁或完成時才會清除工作階段。',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              key: PrivateCloudInvoiceLabWebViewPage.consentKey,
              contentPadding: EdgeInsets.zero,
              value: _controller.consentAccepted,
              onChanged: (value) =>
                  _controller.setConsentAccepted(value ?? false),
              title: const Text('我同意本次一次性前景匯入工作階段'),
              subtitle: const Text('每次重新開始都必須再次同意。'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: PrivateCloudInvoiceLabWebViewPage.startKey,
              onPressed: _controller.canStart ? _start : null,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('開始一次性官方頁面'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActive() {
    final runtime = _controller.buildRuntimeView();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('官方頁面・前景工作階段'),
        actions: [
          IconButton(
            key: PrivateCloudInvoiceLabWebViewPage.officialDetailKey,
            tooltip: '補充官方發票明細',
            onPressed: _controller.canEnrichOfficialInvoiceDetails &&
                    !_officialDetailOpening
                ? _openOfficialDetailEnrichment
                : null,
            icon: _officialDetailOpening
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            key: PrivateCloudInvoiceLabWebViewPage.probeKey,
            tooltip: '頁面相容性檢查',
            onPressed: _controller.canProbeAuthenticatedSelectors
                ? _openProbe
                : null,
            icon: const Icon(Icons.rule_folder_outlined),
          ),
          IconButton(
            key: PrivateCloudInvoiceLabWebViewPage.finishKey,
            tooltip: '完成並清除',
            onPressed: _finish,
            icon: const Icon(Icons.done),
          ),
          IconButton(
            key: PrivateCloudInvoiceLabWebViewPage.cancelKey,
            tooltip: '取消並清除',
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_downloadErrorCode != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.error_outline),
                  title: const Text('CSV 接收未完成'),
                  subtitle: Text(_downloadErrorMessage(_downloadErrorCode!)),
                  trailing: IconButton(
                    onPressed: () =>
                        setState(() => _downloadErrorCode = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            Expanded(
              key: PrivateCloudInvoiceLabWebViewPage.runtimeKey,
              child: runtime ??
                  const Center(child: Text('WebView 工作階段尚未就緒')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress({required String title, required String message}) {
    return Scaffold(
      appBar: AppBar(title: const Text('官方發票一次性匯入 POC')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompleted() {
    return Scaffold(
      appBar: AppBar(title: const Text('工作階段已清除')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('Cookie、快取、網站儲存空間與頁面狀態已清除。'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _controller.resetAfterCompletion,
              child: const Text('重新開始'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailure({required bool canReset}) {
    return Scaffold(
      appBar: AppBar(title: const Text('工作階段無法繼續')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_outlined, size: 56),
              const SizedBox(height: 12),
              Text(
                _controller.errorMessage ?? '未知錯誤',
                textAlign: TextAlign.center,
              ),
              if (canReset) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _controller.resetAfterStartFailure,
                  child: const Text('返回'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _downloadErrorMessage(String code) {
    switch (code) {
      case 'CSV_DOWNLOAD_EXPLICIT_TAP_REQUIRED':
        return '未確認到近期的使用者點擊，已拒絕下載。請直接點擊官方匯出控制項。';
      case 'CSV_DOWNLOAD_URL_REJECTED':
      case 'CSV_HOST_NOT_APPROVED':
      case 'CSV_HTTPS_REQUIRED':
        return '下載來源不是核准的官方 HTTPS 主機。';
      case 'CSV_METADATA_REJECTED':
      case 'CSV_RESPONSE_REJECTED':
      case 'CSV_SIGNATURE_INVALID':
        return '下載內容未通過 CSV 類型或官方欄位簽章檢查。';
      case 'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED':
        return 'CSV 超過本次 POC 的 10 MB 上限。';
      case 'CSV_DOWNLOAD_CANCELLED':
        return '下載已取消，暫存檔已清除。';
      case 'CSV_DOWNLOAD_TIMEOUT':
        return '下載逾時，暫存檔已清除。';
      default:
        return '下載或解析失敗（$code）。未保存 Cookie 或 CSV 原始內容。';
    }
  }
}
