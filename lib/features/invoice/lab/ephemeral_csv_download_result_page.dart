import 'package:flutter/material.dart';

import '../../account/account_record.dart';
import 'official_cloud_invoice_csv_adapter.dart';
import 'private_cloud_invoice_csv_import_page.dart';
import 'private_cloud_invoice_csv_import_service.dart';
import 'private_cloud_invoice_csv_reconciliation_preview.dart';

/// Confirms that the WebView download was parsed and the raw cache file was
/// deleted. The parsed model remains in process memory and can be consumed once
/// by the existing reconciliation-first CSV importer.
class EphemeralCsvDownloadResultPage extends StatelessWidget {
  const EphemeralCsvDownloadResultPage({
    super.key,
    required this.source,
  });

  static const Key openReconciliationKey =
      Key('ephemeral_csv_open_reconciliation');

  final PrivateCloudInvoiceCsvSource source;

  @override
  Widget build(BuildContext context) {
    final preview = source.preview;
    return Scaffold(
      appBar: AppBar(title: const Text('官方 CSV 已安全接收')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user_outlined),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '解析完成，原始 CSV 已刪除',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('來源檔名：${source.fileName}'),
                    Text('發票數：${preview.invoiceCount}'),
                    Text('可覆核：${preview.supportedInvoiceCount}'),
                    Text('受阻擋：${preview.blockedInvoiceCount}'),
                    Text('明細列：${preview.detailRowCount}'),
                    const SizedBox(height: 12),
                    const Text(
                      'Cookie、下載 URL、CSV 原始位元組與暫存路徑均不會寫入資料庫或備份。',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: openReconciliationKey,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PrivateCloudInvoiceCsvImportPage(
                      service: _SingleUsePreloadedCsvImportPort(source),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('進入既有對帳覆核流程'),
            ),
            const SizedBox(height: 8),
            const Text(
              '此 POC 先以單次記憶體來源銜接既有匯入器；下一畫面按下「選擇財政部 CSV 並比對」時，不會再次開啟檔案選擇器。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleUsePreloadedCsvImportPort
    implements PrivateCloudInvoiceCsvImportPort {
  _SingleUsePreloadedCsvImportPort(this._source)
      : _delegate = PrivateCloudInvoiceCsvImportService();

  final PrivateCloudInvoiceCsvImportService _delegate;
  PrivateCloudInvoiceCsvSource? _source;

  @override
  Future<PrivateCloudInvoiceCsvSource?> pickAndPreview() async {
    final source = _source;
    _source = null;
    return source;
  }

  @override
  Future<PrivateCloudInvoiceCsvReconciliationPreview>
      buildReconciliationPreview(OfficialCloudInvoiceCsvPreview preview) {
    return _delegate.buildReconciliationPreview(preview);
  }

  @override
  Future<List<AccountRecord>> listActiveAccounts() {
    return _delegate.listActiveAccounts();
  }

  @override
  Future<PrivateCloudInvoiceCsvImportSummary> importDrafts({
    required OfficialCloudInvoiceCsvPreview preview,
    required Set<String> invoiceIds,
    required AccountRecord account,
  }) {
    return _delegate.importDrafts(
      preview: preview,
      invoiceIds: invoiceIds,
      account: account,
    );
  }
}
