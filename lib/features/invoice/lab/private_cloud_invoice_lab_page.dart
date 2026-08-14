import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_page.dart';
import '../../account/account_record.dart';
import 'cloud_invoice_persistence_models.dart';
import 'private_cloud_invoice_csv_import_page.dart';
import 'private_cloud_invoice_draft_promotion_page.dart';
import 'private_cloud_invoice_lab_config.dart';
import 'private_cloud_invoice_lab_smoke_service.dart';
import 'private_cloud_invoice_lab_webview_page.dart';

class PrivateCloudInvoiceLabPage extends StatefulWidget {
  PrivateCloudInvoiceLabPage({
    super.key,
    PrivateCloudInvoiceLabSmokePort? smokePort,
    this.onOpenWebView,
    this.onOpenCsvImport,
    this.onOpenDraftPromotion,
    this.onOpenAccounts,
  }) : smokePort = smokePort ?? PrivateCloudInvoiceLabSmokeService();

  static const String routeName = 'private-cloud-invoice-lab';
  static const String routePath = '/private-cloud-invoice-lab';
  static const Key webViewButtonKey = Key('private_lab_webview_button');
  static const Key csvImportButtonKey = Key('private_lab_csv_import_button');
  static const Key draftPromotionButtonKey =
      Key('private_lab_draft_promotion_button');
  static const Key accountDropdownKey = Key('private_lab_account_dropdown');
  static const Key accountButtonKey = Key('private_lab_open_accounts');
  static const Key consentKey = Key('private_lab_smoke_consent');
  static const Key runButtonKey = Key('private_lab_smoke_run');
  static const Key cleanupButtonKey = Key('private_lab_smoke_cleanup');
  static const Key resultKey = Key('private_lab_smoke_result');

  final PrivateCloudInvoiceLabSmokePort smokePort;
  final VoidCallback? onOpenWebView;
  final VoidCallback? onOpenCsvImport;
  final VoidCallback? onOpenDraftPromotion;
  final VoidCallback? onOpenAccounts;

  @override
  State<PrivateCloudInvoiceLabPage> createState() =>
      _PrivateCloudInvoiceLabPageState();
}

class _PrivateCloudInvoiceLabPageState
    extends State<PrivateCloudInvoiceLabPage> {
  List<AccountRecord> _accounts = const [];
  String? _selectedAccountId;
  bool _loadingAccounts = true;
  bool _running = false;
  bool _cleaning = false;
  bool _confirmed = false;
  String? _error;
  PrivateCloudInvoiceLabSmokeSnapshot? _snapshot;
  PrivateCloudInvoiceLabCleanupResult? _cleanupResult;

  AccountRecord? get _selectedAccount {
    for (final item in _accounts) {
      if (item.id == _selectedAccountId) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loadingAccounts = true;
      _error = null;
    });
    try {
      final accounts = await widget.smokePort.listActiveAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loadingAccounts = false;
        if (!accounts.any((item) => item.id == _selectedAccountId)) {
          _selectedAccountId = null;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingAccounts = false;
          _error = '帳戶載入失敗：$error';
        });
      }
    }
  }

  Future<void> _runSmoke() async {
    final account = _selectedAccount;
    if (account == null || !_confirmed || _running) return;
    setState(() {
      _running = true;
      _error = null;
      _cleanupResult = null;
    });
    try {
      final result = await widget.smokePort.execute(account);
      if (mounted) setState(() => _snapshot = result);
    } catch (error) {
      if (mounted) setState(() => _error = '非正式草稿驗證失敗：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _cleanupSmoke() async {
    final account = _selectedAccount;
    if (account == null || _cleaning) return;
    setState(() {
      _cleaning = true;
      _error = null;
    });
    try {
      final result = await widget.smokePort.cleanup(account);
      if (mounted) {
        setState(() {
          _cleanupResult = result;
          _snapshot = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'LAB 驗證資料清理失敗：$error');
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  void _openWebView() {
    if (widget.onOpenWebView != null) return widget.onOpenWebView!();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PrivateCloudInvoiceLabWebViewPage(),
      ),
    );
  }

  void _openCsvImport() {
    if (widget.onOpenCsvImport != null) return widget.onOpenCsvImport!();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateCloudInvoiceCsvImportPage(),
      ),
    );
  }

  void _openDraftPromotion() {
    if (widget.onOpenDraftPromotion != null) {
      return widget.onOpenDraftPromotion!();
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateCloudInvoiceDraftPromotionPage(),
      ),
    );
  }

  void _openAccounts() {
    if (widget.onOpenAccounts != null) return widget.onOpenAccounts!();
    context.push(AccountPage.routePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('私有雲端發票 LAB')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _warningCard(),
            const SizedBox(height: 12),
            _actionCard(
              title: '一次性 WebView 驗證',
              description:
                  '自行登入財政部頁面並執行 selector capability probe。App 不保存帳密、Cookie、DOM、HTML、截圖或發票內容。',
              buttonKey: PrivateCloudInvoiceLabPage.webViewButtonKey,
              buttonLabel: '開啟一次性 WebView',
              icon: Icons.open_in_browser,
              onPressed: _openWebView,
            ),
            const SizedBox(height: 12),
            _actionCard(
              title: '財政部 CSV 手動匯入驗證',
              description:
                  '由外部瀏覽器下載官方 CSV，進行格式檢查、對帳覆核、既有交易補充與未比對草稿建立。',
              buttonKey: PrivateCloudInvoiceLabPage.csvImportButtonKey,
              buttonLabel: '開啟 CSV 匯入 LAB',
              icon: Icons.upload_file_outlined,
              onPressed: _openCsvImport,
            ),
            const SizedBox(height: 12),
            _actionCard(
              title: '雲端發票草稿轉正式支出',
              description:
                  '檢視尚未轉正式的草稿，批次選取並覆核分類、成員、標籤；通過重複檢查與最終確認後才建立正式支出。',
              buttonKey: PrivateCloudInvoiceLabPage.draftPromotionButtonKey,
              buttonLabel: '開啟草稿轉正式覆核',
              icon: Icons.post_add_outlined,
              onPressed: _openDraftPromotion,
            ),
            const SizedBox(height: 12),
            _smokeCard(),
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
            if (_snapshot != null) ...[
              const SizedBox(height: 12),
              _resultCard(_snapshot!),
            ],
            if (_cleanupResult != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '已清理 ${_cleanupResult!.totalDeleted} 筆 LAB 驗證資料；未修改任何正式帳目。',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _warningCard() {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '專用實機驗證版本',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text('版本：${PrivateCloudInvoiceLabConfig.validationVersion}'),
            Text('此入口不執行背景同步；正式支出只能經由逐筆覆核與明確確認建立。'),
          ],
        ),
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String description,
    required Key buttonKey,
    required String buttonLabel,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: buttonKey,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smokeCard() {
    final account = _selectedAccount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Canonical 非正式草稿驗證',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '固定建立 1 元、日期 2000-01-01、時間／幣別／稅額未知的 LAB 草稿。不建立商家、不修改既有帳目，也不寫入正式交易表。',
            ),
            const SizedBox(height: 12),
            if (_loadingAccounts)
              const Center(child: CircularProgressIndicator())
            else if (_accounts.isEmpty) ...[
              const Text('目前沒有可使用的有效帳戶。'),
              OutlinedButton.icon(
                key: PrivateCloudInvoiceLabPage.accountButtonKey,
                onPressed: _openAccounts,
                icon: const Icon(Icons.add_card),
                label: const Text('前往帳戶頁'),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                key: PrivateCloudInvoiceLabPage.accountDropdownKey,
                initialValue: _selectedAccountId,
                decoration: const InputDecoration(
                  labelText: '選擇既有帳戶',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final item in _accounts)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text('${item.displayName}・${item.currency.code}'),
                    ),
                ],
                onChanged: _running || _cleaning
                    ? null
                    : (value) => setState(() {
                          _selectedAccountId = value;
                          _snapshot = null;
                          _cleanupResult = null;
                        }),
              ),
              TextButton.icon(
                onPressed: _loadAccounts,
                icon: const Icon(Icons.refresh),
                label: const Text('重新載入帳戶'),
              ),
            ],
            CheckboxListTile(
              key: PrivateCloudInvoiceLabPage.consentKey,
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: _running || _cleaning
                  ? null
                  : (value) =>
                      setState(() => _confirmed = value ?? false),
              title: const Text('我了解此操作只建立非正式 LAB 草稿'),
              subtitle: const Text('草稿不會出現在正式帳目列表。'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: PrivateCloudInvoiceLabPage.runButtonKey,
                    onPressed: account != null &&
                            _confirmed &&
                            !_running &&
                            !_cleaning
                        ? _runSmoke
                        : null,
                    icon: const Icon(Icons.science_outlined),
                    label: Text(_running ? '執行中' : '執行驗證'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: PrivateCloudInvoiceLabPage.cleanupButtonKey,
                    onPressed: account != null && !_running && !_cleaning
                        ? _cleanupSmoke
                        : null,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: Text(_cleaning ? '清理中' : '清理 LAB 資料'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(PrivateCloudInvoiceLabSmokeSnapshot snapshot) {
    final success = snapshot.status == CloudInvoicePersistenceStatus.committed ||
        snapshot.status == CloudInvoicePersistenceStatus.alreadyApplied;
    return Card(
      key: PrivateCloudInvoiceLabPage.resultKey,
      color: success
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '結果：${snapshot.status.name}\n'
          '訊息：${snapshot.message}\n'
          'Operation key：${snapshot.operationKey}\n'
          'Draft ID：${snapshot.draftId ?? '沿用既有結果'}\n'
          'Draft／Operation／Audit：${snapshot.draftCount}／${snapshot.operationCount}／${snapshot.auditCount}\n'
          '${snapshot.transactionCountUnchanged ? '正式交易筆數未改變' : '警告：正式交易筆數發生變化'}',
        ),
      ),
    );
  }
}
