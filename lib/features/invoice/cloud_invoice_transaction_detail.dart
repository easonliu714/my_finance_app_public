import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v14.dart';
import '../transaction/transaction_record.dart';
import 'cloud_invoice_candidate.dart';
import 'lab/canonical_cloud_invoice_persistence_codec.dart';
import 'lab/cloud_invoice_reconciliation_models.dart';

abstract class CloudInvoiceTransactionDetailPort {
  Future<CloudInvoiceTransactionDetail?> findByTransactionId(
    String transactionId,
  );
}

class ProductionCloudInvoiceTransactionDetailPort
    implements CloudInvoiceTransactionDetailPort {
  ProductionCloudInvoiceTransactionDetailPort({
    Future<Database> Function()? databaseProvider,
  }) : _databaseProvider = databaseProvider ??
            (() => ProductionDatabaseCoordinator.instance.database);

  final Future<Database> Function() _databaseProvider;

  @override
  Future<CloudInvoiceTransactionDetail?> findByTransactionId(
    String transactionId,
  ) async {
    final db = await _databaseProvider();
    await createCanonicalProductionV14Tables(db);
    final rows = await db.rawQuery(
      '''
      SELECT
        m.*,
        p.draft_id AS promotion_draft_id,
        p.promotion_key AS promotion_key,
        p.draft_operation_key AS promotion_draft_operation_key,
        p.created_at AS promotion_created_at
      FROM cloud_invoice_metadata_links m
      LEFT JOIN cloud_invoice_draft_promotions p
        ON p.transaction_id = m.transaction_id
      WHERE m.transaction_id = ?
      ORDER BY m.created_at DESC
      LIMIT 1
      ''',
      <Object?>[transactionId],
    );
    if (rows.isEmpty) return null;
    return CloudInvoiceTransactionDetail.fromRow(rows.single);
  }
}

class CloudInvoiceTransactionDetail {
  const CloudInvoiceTransactionDetail({
    required this.id,
    required this.operationKey,
    required this.transactionId,
    required this.candidateReference,
    required this.invoiceNumber,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.invoiceDate,
    required this.timePrecision,
    required this.timeSource,
    required this.currencySource,
    required this.lineItems,
    required this.createdAt,
    this.currencyCode,
    this.taxAmount,
    this.merchantId,
    this.draftId,
    this.promotionKey,
    this.draftOperationKey,
    this.promotionCreatedAt,
  });

  factory CloudInvoiceTransactionDetail.fromRow(Map<String, Object?> row) {
    final timePrecisionName = row['time_precision'] as String? ?? '';
    final timeSourceName = row['time_source'] as String? ?? '';
    final currencySourceName = row['currency_source'] as String? ?? '';
    return CloudInvoiceTransactionDetail(
      id: row['id'] as String,
      operationKey: row['operation_key'] as String,
      transactionId: row['transaction_id'] as String,
      candidateReference: row['candidate_reference'] as String,
      invoiceNumber: row['invoice_number'] as String? ?? '',
      sellerIdentifier: row['seller_identifier'] as String? ?? '',
      sellerName: row['seller_name'] as String? ?? '',
      invoiceDate: DateTime.parse(row['invoice_date'] as String),
      timePrecision: _enumByName(
        CloudInvoiceTimePrecision.values,
        timePrecisionName,
        CloudInvoiceTimePrecision.dateOnly,
      ),
      timeSource: _enumByName(
        CloudInvoiceTimeSource.values,
        timeSourceName,
        CloudInvoiceTimeSource.unknown,
      ),
      currencyCode: row['currency_code'] as String?,
      currencySource: _enumByName(
        CloudInvoiceCurrencySource.values,
        currencySourceName,
        CloudInvoiceCurrencySource.unknown,
      ),
      taxAmount: (row['tax_amount'] as num?)?.toDouble(),
      merchantId: row['merchant_id'] as String?,
      lineItems: decodeCloudInvoiceLineItems(
        row['line_items_json'] as String? ??
            '{"version":1,"items":[]}',
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      draftId: row['promotion_draft_id'] as String?,
      promotionKey: row['promotion_key'] as String?,
      draftOperationKey: row['promotion_draft_operation_key'] as String?,
      promotionCreatedAt: _nullableDateTime(row['promotion_created_at']),
    );
  }

  final String id;
  final String operationKey;
  final String transactionId;
  final String candidateReference;
  final String invoiceNumber;
  final String sellerIdentifier;
  final String sellerName;
  final DateTime invoiceDate;
  final CloudInvoiceTimePrecision timePrecision;
  final CloudInvoiceTimeSource timeSource;
  final String? currencyCode;
  final CloudInvoiceCurrencySource currencySource;
  final double? taxAmount;
  final String? merchantId;
  final List<CloudInvoiceLineItem> lineItems;
  final DateTime createdAt;
  final String? draftId;
  final String? promotionKey;
  final String? draftOperationKey;
  final DateTime? promotionCreatedAt;

  double get lineItemTotal => lineItems.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      );

  bool amountMatches(double transactionAmount) {
    return (lineItemTotal - transactionAmount).abs() <= 0.01;
  }

  String get dateTimeLabel {
    if (timePrecision == CloudInvoiceTimePrecision.dateOnly) {
      return '${DateFormat('yyyy-MM-dd').format(invoiceDate)}｜時間未提供（僅日期）';
    }
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(invoiceDate);
  }

  String get timeSourceLabel {
    if (timePrecision == CloudInvoiceTimePrecision.dateOnly &&
        timeSource == CloudInvoiceTimeSource.unknown) {
      return '官方 CSV 僅提供日期';
    }
    switch (timeSource) {
      case CloudInvoiceTimeSource.unknown:
        return '來源未知';
      case CloudInvoiceTimeSource.officialInvoiceIssuedAt:
        return '官方發票開立時間';
      case CloudInvoiceTimeSource.officialDetailPage:
        return '官方發票明細頁';
      case CloudInvoiceTimeSource.merchantPosCheckout:
        return '商家 POS 結帳時間';
      case CloudInvoiceTimeSource.emailReceipt:
        return '電子收據時間';
      case CloudInvoiceTimeSource.invoiceQrCode:
        return '發票 QR Code';
      case CloudInvoiceTimeSource.userEntered:
        return '使用者輸入';
    }
  }

  String get currencySourceLabel {
    switch (currencySource) {
      case CloudInvoiceCurrencySource.unknown:
        return '來源未知';
      case CloudInvoiceCurrencySource.officialDetail:
        return '官方發票明細';
      case CloudInvoiceCurrencySource.officialDetailPage:
        return '官方發票明細頁';
      case CloudInvoiceCurrencySource.merchantData:
        return '商家資料';
      case CloudInvoiceCurrencySource.loyaltyAppDisplay:
        return '會員／載具 App 顯示';
      case CloudInvoiceCurrencySource.inferredDefault:
        return '預設值推定';
      case CloudInvoiceCurrencySource.userConfirmed:
        return '使用者確認／歸戶帳戶';
    }
  }
}

class CloudInvoiceTransactionDetailSection extends StatefulWidget {
  CloudInvoiceTransactionDetailSection({
    super.key,
    required this.transaction,
    this.onSupplementRequested,
    CloudInvoiceTransactionDetailPort? port,
  }) : port = port ?? ProductionCloudInvoiceTransactionDetailPort();

  static const sectionKey = Key('cloud_invoice_transaction_detail_section');
  static const openKey = Key('cloud_invoice_transaction_detail_open');

  final TransactionRecord transaction;
  final VoidCallback? onSupplementRequested;
  final CloudInvoiceTransactionDetailPort port;

  @override
  State<CloudInvoiceTransactionDetailSection> createState() =>
      _CloudInvoiceTransactionDetailSectionState();
}

class _CloudInvoiceTransactionDetailSectionState
    extends State<CloudInvoiceTransactionDetailSection> {
  late Future<CloudInvoiceTransactionDetail?> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.port.findByTransactionId(widget.transaction.id);
  }

  @override
  void didUpdateWidget(CloudInvoiceTransactionDetailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transaction.id != widget.transaction.id ||
        oldWidget.port != widget.port) {
      _detailFuture = widget.port.findByTransactionId(widget.transaction.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudInvoiceTransactionDetail?>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                title: const Text('發票明細讀取失敗'),
                subtitle: Text('${snapshot.error}'),
                trailing: IconButton(
                  tooltip: '重試',
                  onPressed: () => setState(() {
                    _detailFuture = widget.port
                        .findByTransactionId(widget.transaction.id);
                  }),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          );
        }
        final detail = snapshot.data;
        if (detail == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Card(
            key: CloudInvoiceTransactionDetailSection.sectionKey,
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text(
                '發票明細',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${detail.invoiceNumber}｜${detail.dateTimeLabel}\n'
                '${detail.currencyCode ?? '幣別未提供'}｜${detail.currencySourceLabel}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                key: CloudInvoiceTransactionDetailSection.openKey,
                tooltip: '查看完整發票明細',
                onPressed: () => _openDetail(context, detail),
                icon: const Icon(Icons.chevron_right),
              ),
              onTap: () => _openDetail(context, detail),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    CloudInvoiceTransactionDetail detail,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => CloudInvoiceTransactionDetailSheet(
        transaction: widget.transaction,
        detail: detail,
        onSupplementRequested: widget.onSupplementRequested,
      ),
    );
  }
}

class CloudInvoiceTransactionDetailSheet extends StatelessWidget {
  const CloudInvoiceTransactionDetailSheet({
    super.key,
    required this.transaction,
    required this.detail,
    this.onSupplementRequested,
  });

  static const sheetKey = Key('cloud_invoice_transaction_detail_sheet');
  static const supplementKey = Key('cloud_invoice_supplement_items');

  final TransactionRecord transaction;
  final CloudInvoiceTransactionDetail detail;
  final VoidCallback? onSupplementRequested;

  @override
  Widget build(BuildContext context) {
    final number = NumberFormat('#,##0.##');
    final matches = detail.amountMatches(transaction.amount);
    final seller = detail.sellerName.trim().isEmpty
        ? '未提供商家'
        : detail.sellerName.trim();
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: ListView(
          key: sheetKey,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              '發票明細（唯讀）',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              '官方明細維持唯讀；缺少的項目可補充到正式交易備註，不會改寫官方資料。',
            ),
            if (onSupplementRequested != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: supplementKey,
                onPressed: () {
                  final callback = onSupplementRequested;
                  Navigator.of(context).pop();
                  callback?.call();
                },
                icon: const Icon(Icons.playlist_add_outlined),
                label: const Text('補充未列入明細'),
              ),
            ],
            const SizedBox(height: 12),
            _DetailCard(
              title: detail.invoiceNumber.isEmpty
                  ? '發票號碼未提供'
                  : detail.invoiceNumber,
              children: [
                _DetailRow(label: '賣方名稱', value: seller),
                _DetailRow(
                  label: '賣方統編',
                  value: detail.sellerIdentifier.trim().isEmpty
                      ? '未提供'
                      : detail.sellerIdentifier,
                ),
                _DetailRow(label: '發票日期／時間', value: detail.dateTimeLabel),
                _DetailRow(label: '時間來源', value: detail.timeSourceLabel),
                _DetailRow(
                  label: '幣別',
                  value: detail.currencyCode?.trim().isNotEmpty == true
                      ? detail.currencyCode!
                      : '未提供',
                ),
                _DetailRow(label: '幣別來源', value: detail.currencySourceLabel),
                if (detail.taxAmount != null)
                  _DetailRow(
                    label: '稅額',
                    value: number.format(detail.taxAmount),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailCard(
              title: '消費明細（${detail.lineItems.length}）',
              children: detail.lineItems.isEmpty
                  ? const [Text('沒有可顯示的品項資料。')]
                  : [
                      for (final item in detail.lineItems)
                        _LineItemRow(item: item, number: number),
                    ],
            ),
            const SizedBox(height: 12),
            Card(
              color: matches
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      matches ? '金額驗證一致' : '金額需要覆核',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text('品項加總：${number.format(detail.lineItemTotal)}'),
                    Text('正式交易：${number.format(transaction.amount)}'),
                    if (!matches)
                      const Text('本區只顯示差異，不會自動改寫正式交易金額。'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('來源與稽核參照'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _DetailRow(
                  label: '候選參照',
                  value: detail.candidateReference,
                ),
                _DetailRow(
                  label: 'Metadata operation',
                  value: detail.operationKey,
                ),
                _DetailRow(
                  label: '原草稿 ID',
                  value: detail.draftId ?? '未提供',
                ),
                _DetailRow(
                  label: '草稿 operation',
                  value: detail.draftOperationKey ?? '未提供',
                ),
                _DetailRow(
                  label: '轉正式 operation',
                  value: detail.promotionKey ?? '未提供',
                ),
                _DetailRow(
                  label: 'Metadata 建立時間',
                  value: DateFormat('yyyy-MM-dd HH:mm:ss')
                      .format(detail.createdAt.toLocal()),
                ),
                if (detail.promotionCreatedAt != null)
                  _DetailRow(
                    label: '轉正式時間',
                    value: DateFormat('yyyy-MM-dd HH:mm:ss')
                        .format(detail.promotionCreatedAt!.toLocal()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.item, required this.number});

  final CloudInvoiceLineItem item;
  final NumberFormat number;

  @override
  Widget build(BuildContext context) {
    final details = <String>[];
    if (item.quantity != null) {
      details.add('數量 ${number.format(item.quantity)}');
    }
    if (item.unitPrice != null) {
      details.add('單價 ${number.format(item.unitPrice)}');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name),
                if (details.isNotEmpty)
                  Text(
                    details.join('｜'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            number.format(item.amount),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

T _enumByName<T extends Enum>(List<T> values, String name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

DateTime? _nullableDateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}
