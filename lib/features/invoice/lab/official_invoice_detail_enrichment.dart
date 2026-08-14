import 'dart:convert';

import '../cloud_invoice_candidate.dart';

const int officialInvoiceDetailSelectorProfileVersion = 7;

enum OfficialInvoiceDetailSelectionScope {
  singleInvoice,
  selectedInvoices,
  currentPage,
}

class OfficialInvoiceDetailTarget {
  const OfficialInvoiceDetailTarget({
    required this.invoiceNumber,
    required this.selected,
    required this.expectedTotal,
    required this.sellerIdentifier,
    required this.sellerName,
  });

  factory OfficialInvoiceDetailTarget.fromJson(Map<String, Object?> json) {
    return OfficialInvoiceDetailTarget(
      invoiceNumber: json['invoiceNumber']?.toString() ?? '',
      selected: json['selected'] == true,
      expectedTotal: (json['expectedTotal'] as num?)?.toDouble(),
      sellerIdentifier: json['sellerIdentifier']?.toString() ?? '',
      sellerName: json['sellerName']?.toString() ?? '',
    );
  }

  final String invoiceNumber;
  final bool selected;
  final double? expectedTotal;
  final String sellerIdentifier;
  final String sellerName;
}

class OfficialInvoiceDetailTargetReport {
  const OfficialInvoiceDetailTargetReport({
    required this.routeApproved,
    required this.selectorProfileVersion,
    required this.targets,
    this.errorCode,
  });

  factory OfficialInvoiceDetailTargetReport.fromRaw(Object? raw) {
    final decoded = _decodeObject(raw);
    if (decoded is! Map) {
      return const OfficialInvoiceDetailTargetReport(
        routeApproved: false,
        selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
        targets: <OfficialInvoiceDetailTarget>[],
        errorCode: 'DETAIL_TARGET_RESPONSE_INVALID',
      );
    }
    final map = Map<String, Object?>.from(decoded.cast<String, Object?>());
    final rawTargets = map['targets'];
    final targets = rawTargets is List
        ? rawTargets
              .whereType<Map>()
              .map(
                (item) => OfficialInvoiceDetailTarget.fromJson(
                  Map<String, Object?>.from(item.cast<String, Object?>()),
                ),
              )
              .where((item) => item.invoiceNumber.isNotEmpty)
              .toList(growable: false)
        : const <OfficialInvoiceDetailTarget>[];
    return OfficialInvoiceDetailTargetReport(
      routeApproved: map['routeApproved'] == true,
      selectorProfileVersion:
          (map['selectorProfileVersion'] as num?)?.toInt() ??
          officialInvoiceDetailSelectorProfileVersion,
      targets: List.unmodifiable(targets),
      errorCode: map['errorCode']?.toString(),
    );
  }

  final bool routeApproved;
  final int selectorProfileVersion;
  final List<OfficialInvoiceDetailTarget> targets;
  final String? errorCode;

  int get selectedCount => targets.where((item) => item.selected).length;
  bool get canStart => routeApproved && targets.isNotEmpty;
}

class OfficialInvoiceDetailLineItem {
  const OfficialInvoiceDetailLineItem({
    required this.name,
    required this.amount,
    this.quantity,
    this.unitPrice,
  });

  factory OfficialInvoiceDetailLineItem.fromJson(Map<String, Object?> json) {
    return OfficialInvoiceDetailLineItem(
      name: json['name']?.toString().trim() ?? '',
      quantity: (json['quantity'] as num?)?.toDouble(),
      unitPrice: (json['unitPrice'] as num?)?.toDouble(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  final String name;
  final double? quantity;
  final double? unitPrice;
  final double amount;

  CloudInvoiceLineItem toCandidateItem() => CloudInvoiceLineItem(
    name: name,
    quantity: quantity,
    unitPrice: unitPrice,
    amount: amount,
  );
}

class OfficialInvoiceDetailEnrichment {
  const OfficialInvoiceDetailEnrichment({
    required this.requestedInvoiceNumber,
    required this.invoiceNumber,
    required this.selectorProfileVersion,
    required this.fetchedAt,
    required this.success,
    required this.invoiceIdentityMatches,
    required this.detailTotalInternallyConsistent,
    required this.detailTotalMatchesCsv,
    required this.sellerIdentifierConsistent,
    required this.lineItems,
    this.exactTimestamp,
    this.currencyCode,
    this.officialStatus,
    this.sellerIdentifier,
    this.sellerName,
    this.expectedTotal,
    this.detailTotal,
    this.officialTaxAmount,
    this.officialTaxLabel,
    this.lineItemSubtotal,
    this.unallocatedDifference,
    this.errorCode,
    this.warningCode,
    this.declaredItemCount,
    this.omittedItemCount = 0,
    this.lineItemsTruncated = false,
    this.dialogDetected = false,
    this.summaryTableDetected = false,
    this.itemTableDetected = false,
    this.detectedItemRowCount = 0,
    this.initialItemRowCount = 0,
    this.requiredVisibleItemCount = 0,
    this.pageSizeControlDetected = false,
    this.pageSize100OptionDetected = false,
    this.pageSize100SelectionObserved = false,
    this.pageSizeApplyControlDetected = false,
    this.pageSizeApplyTriggered = false,
    this.loadingMaskObserved = false,
  });

  factory OfficialInvoiceDetailEnrichment.fromJson(Map<String, Object?> json) {
    final rawItems = json['lineItems'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => OfficialInvoiceDetailLineItem.fromJson(
                  Map<String, Object?>.from(item.cast<String, Object?>()),
                ),
              )
              .where((item) => item.name.isNotEmpty)
              .toList(growable: false)
        : const <OfficialInvoiceDetailLineItem>[];
    return OfficialInvoiceDetailEnrichment(
      requestedInvoiceNumber:
          json['requestedInvoiceNumber']?.toString().trim() ?? '',
      invoiceNumber: json['invoiceNumber']?.toString().trim() ?? '',
      selectorProfileVersion:
          (json['selectorProfileVersion'] as num?)?.toInt() ??
          officialInvoiceDetailSelectorProfileVersion,
      fetchedAt:
          DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      success: json['success'] == true,
      invoiceIdentityMatches: json['invoiceIdentityMatches'] == true,
      detailTotalInternallyConsistent:
          json['detailTotalInternallyConsistent'] == true,
      detailTotalMatchesCsv: json['detailTotalMatchesCsv'] == true,
      sellerIdentifierConsistent: json['sellerIdentifierConsistent'] == true,
      lineItems: List.unmodifiable(items),
      exactTimestamp: DateTime.tryParse(
        json['exactTimestamp']?.toString() ?? '',
      ),
      currencyCode: _nullableText(json['currencyCode']),
      officialStatus: _nullableText(json['officialStatus']),
      sellerIdentifier: _nullableText(json['sellerIdentifier']),
      sellerName: _nullableText(json['sellerName']),
      expectedTotal: (json['expectedTotal'] as num?)?.toDouble(),
      detailTotal: (json['detailTotal'] as num?)?.toDouble(),
      officialTaxAmount: (json['officialTaxAmount'] as num?)?.toDouble(),
      officialTaxLabel: _nullableText(json['officialTaxLabel']),
      lineItemSubtotal: (json['lineItemSubtotal'] as num?)?.toDouble(),
      unallocatedDifference: (json['unallocatedDifference'] as num?)
          ?.toDouble(),
      errorCode: _nullableText(json['errorCode']),
      warningCode: _nullableText(json['warningCode']),
      declaredItemCount: (json['declaredItemCount'] as num?)?.toInt(),
      omittedItemCount: (json['omittedItemCount'] as num?)?.toInt() ?? 0,
      lineItemsTruncated: json['lineItemsTruncated'] == true,
      dialogDetected: json['dialogDetected'] == true,
      summaryTableDetected: json['summaryTableDetected'] == true,
      itemTableDetected: json['itemTableDetected'] == true,
      detectedItemRowCount:
          (json['detectedItemRowCount'] as num?)?.toInt() ?? items.length,
      initialItemRowCount: (json['initialItemRowCount'] as num?)?.toInt() ?? 0,
      requiredVisibleItemCount:
          (json['requiredVisibleItemCount'] as num?)?.toInt() ?? 0,
      pageSizeControlDetected: json['pageSizeControlDetected'] == true,
      pageSize100OptionDetected: json['pageSize100OptionDetected'] == true,
      pageSize100SelectionObserved:
          json['pageSize100SelectionObserved'] == true,
      pageSizeApplyControlDetected:
          json['pageSizeApplyControlDetected'] == true,
      pageSizeApplyTriggered: json['pageSizeApplyTriggered'] == true,
      loadingMaskObserved: json['loadingMaskObserved'] == true,
    );
  }

  final String requestedInvoiceNumber;
  final String invoiceNumber;
  final int selectorProfileVersion;
  final DateTime fetchedAt;
  final bool success;
  final bool invoiceIdentityMatches;
  final bool detailTotalInternallyConsistent;
  final bool detailTotalMatchesCsv;
  final bool sellerIdentifierConsistent;
  final List<OfficialInvoiceDetailLineItem> lineItems;
  final DateTime? exactTimestamp;
  final String? currencyCode;
  final String? officialStatus;
  final String? sellerIdentifier;
  final String? sellerName;
  final double? expectedTotal;
  final double? detailTotal;

  /// Explicit amount read from an allowlisted official-page tax label.
  final double? officialTaxAmount;

  /// Exact normalized label that supplied [officialTaxAmount].
  final String? officialTaxLabel;

  /// Sum of product/service rows before an optional standardized tax row.
  final double? lineItemSubtotal;

  /// Official total minus product subtotal and explicit official tax.
  final double? unallocatedDifference;

  final String? errorCode;

  /// Non-blocking governed warning, such as an official detail list exceeding
  /// the supported visible 100 rows.
  final String? warningCode;
  final int? declaredItemCount;
  final int omittedItemCount;
  final bool lineItemsTruncated;

  bool get hasUsableItemRows =>
      detailTotalInternallyConsistent || lineItemsTruncated;

  /// Human review is still required, but this condition must not block draft
  /// or formal transaction creation when the first 100 rows are readable.
  bool get hasNonBlockingItemWarning =>
      lineItemsTruncated && warningCode != null;

  /// Safe, allowlisted diagnostics only. No raw DOM, HTML, URL or credentials.
  final bool dialogDetected;
  final bool summaryTableDetected;
  final bool itemTableDetected;
  final int detectedItemRowCount;
  final int initialItemRowCount;
  final int requiredVisibleItemCount;
  final bool pageSizeControlDetected;
  final bool pageSize100OptionDetected;
  final bool pageSize100SelectionObserved;
  final bool pageSizeApplyControlDetected;
  final bool pageSizeApplyTriggered;
  final bool loadingMaskObserved;

  bool get hasExplicitOfficialTax =>
      officialTaxAmount != null && officialTaxLabel != null;

  double? get positiveEstimatedTaxAmount {
    if (hasExplicitOfficialTax ||
        lineItemsTruncated ||
        !invoiceIdentityMatches ||
        !detailTotalMatchesCsv ||
        exactTimestamp == null ||
        detailTotal == null ||
        lineItemSubtotal == null ||
        lineItems.isEmpty) {
      return null;
    }
    final difference = detailTotal! - lineItemSubtotal!;
    if (difference <= 0.005 ||
        (unallocatedDifference != null &&
            (unallocatedDifference! - difference).abs() > 0.01)) {
      return null;
    }
    return difference;
  }

  bool get canUseUserConfirmedEstimatedTax =>
      positiveEstimatedTaxAmount != null && sellerIdentifierConsistent;

  bool get canUpgradeTime =>
      success &&
      invoiceIdentityMatches &&
      hasUsableItemRows &&
      detailTotalMatchesCsv &&
      exactTimestamp != null;

  bool get canUpgradeCurrency =>
      success &&
      invoiceIdentityMatches &&
      hasUsableItemRows &&
      detailTotalMatchesCsv &&
      currencyCode != null;

  bool get canUseOfficialLineItems =>
      success &&
      invoiceIdentityMatches &&
      hasUsableItemRows &&
      detailTotalMatchesCsv &&
      lineItems.isNotEmpty;

  bool isCompatibleWithCandidate(CloudInvoiceCandidate candidate) {
    return invoiceIdentityMatches &&
        candidate.invoiceNumber.trim().toUpperCase() ==
            invoiceNumber.trim().toUpperCase() &&
        detailTotalMatchesCsv;
  }

  CloudInvoiceCandidate applyValidatedValues(CloudInvoiceCandidate candidate) {
    if (!isCompatibleWithCandidate(candidate)) return candidate;
    return CloudInvoiceCandidate(
      source: candidate.source,
      status: candidate.status,
      invoiceNumber: candidate.invoiceNumber,
      invoiceDate: canUpgradeTime ? exactTimestamp! : candidate.invoiceDate,
      sellerIdentifier: candidate.sellerIdentifier,
      sellerName: candidate.sellerName,
      totalAmount: candidate.totalAmount,
      carrierType: candidate.carrierType,
      carrierMaskedId: candidate.carrierMaskedId,
      fetchedAt: candidate.fetchedAt,
      taxAmount: hasExplicitOfficialTax
          ? officialTaxAmount
          : candidate.taxAmount,
      buyerIdentifier: candidate.buyerIdentifier,
      lineItems: canUseOfficialLineItems
          ? lineItems
                .map((item) => item.toCandidateItem())
                .toList(growable: false)
          : candidate.lineItems,
      rawPayload: candidate.rawPayload,
      confidence: candidate.confidence,
      warnings: candidate.warnings,
      errorCategory: candidate.errorCategory,
      errorMessage: candidate.errorMessage,
      duplicateKeyOverride: candidate.duplicateKeyOverride,
    );
  }
}

class OfficialInvoiceDetailProgress {
  const OfficialInvoiceDetailProgress({
    required this.current,
    required this.total,
    required this.invoiceNumber,
    required this.message,
  });

  final int current;
  final int total;
  final String invoiceNumber;
  final String message;
}

enum OfficialInvoiceDetailTraceStatus {
  pending,
  running,
  success,
  review,
  failed,
  cancelledActive,
  notStartedAfterCancel,
  missingTerminalResult,
}

class OfficialInvoiceDetailTraceItem {
  const OfficialInvoiceDetailTraceItem({
    required this.invoiceNumber,
    required this.ordinal,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.reasonCode,
  });

  final String invoiceNumber;
  final int ordinal;
  final OfficialInvoiceDetailTraceStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? reasonCode;

  bool get isTerminal => switch (status) {
    OfficialInvoiceDetailTraceStatus.pending ||
    OfficialInvoiceDetailTraceStatus.running => false,
    _ => true,
  };
}

class OfficialInvoiceDetailBatchResult {
  const OfficialInvoiceDetailBatchResult({
    required this.requestedCount,
    required this.results,
    required this.cancelled,
    this.traces = const <OfficialInvoiceDetailTraceItem>[],
    this.errorCode,
  });

  final int requestedCount;
  final List<OfficialInvoiceDetailEnrichment> results;
  final bool cancelled;
  final List<OfficialInvoiceDetailTraceItem> traces;
  final String? errorCode;

  int get successCount => results.where((item) => item.success).length;
  int get failedCount => results.length - successCount;
  int get truncatedCount =>
      results.where((item) => item.lineItemsTruncated).length;
  int get terminalTraceCount => traces.where((item) => item.isTerminal).length;
  int get unprocessedCount => traces.where((item) {
    return item.status == OfficialInvoiceDetailTraceStatus.cancelledActive ||
        item.status == OfficialInvoiceDetailTraceStatus.notStartedAfterCancel ||
        item.status == OfficialInvoiceDetailTraceStatus.missingTerminalResult;
  }).length;

  List<OfficialInvoiceDetailTraceItem> get unprocessedTraces => traces
      .where((item) {
        return item.status ==
                OfficialInvoiceDetailTraceStatus.cancelledActive ||
            item.status ==
                OfficialInvoiceDetailTraceStatus.notStartedAfterCancel ||
            item.status ==
                OfficialInvoiceDetailTraceStatus.missingTerminalResult;
      })
      .toList(growable: false);

  Map<String, int> get failureCounts {
    final counts = <String, int>{};
    for (final item in results.where((item) => !item.success)) {
      final code = item.errorCode ?? 'DETAIL_UNKNOWN_FAILURE';
      counts[code] = (counts[code] ?? 0) + 1;
    }
    for (final trace in unprocessedTraces) {
      final code = trace.reasonCode ?? 'DETAIL_MISSING_TERMINAL_RESULT';
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return Map.unmodifiable(counts);
  }
}

abstract interface class OfficialInvoiceDetailEnrichmentRuntime {
  Future<OfficialInvoiceDetailTargetReport> inspectOfficialDetailTargets();

  Future<OfficialInvoiceDetailBatchResult> enrichOfficialInvoiceDetails({
    required OfficialInvoiceDetailSelectionScope scope,
    String? singleInvoiceNumber,
    required void Function(OfficialInvoiceDetailProgress progress) onProgress,
  });

  Future<void> cancelOfficialInvoiceDetailEnrichment();
}

String officialInvoiceDetailFailureLabel(String code) {
  return switch (code) {
    'DETAIL_NO_DIALOG' => '未偵測到官方發票明細視窗',
    'DETAIL_RENDER_TIMEOUT' => '官方明細內容載入逾時',
    'DETAIL_INVOICE_IDENTITY_MISMATCH' => '明細發票號碼與目標不一致',
    'DETAIL_REQUIRED_FIELD_MISSING' => '官方明細缺少必要欄位',
    'DETAIL_ITEM_TABLE_NOT_FOUND' => '找不到官方消費明細表格',
    'DETAIL_ITEM_TOTAL_NOT_FOUND' => '找不到官方明細的合計項目數，已停止部分匯入',
    'DETAIL_ITEM_PAGE_SIZE_100_NOT_AVAILABLE' => '明細品項無法切換為每頁 100 筆',
    'DETAIL_ITEM_PAGE_SIZE_APPLY_NOT_TRIGGERED' => '已選擇每頁 100 筆，但未成功觸發官方表格更新按鈕',
    'DETAIL_ITEM_COUNT_EXCEEDS_SUPPORTED_LIMIT' => '單張發票品項超過 100 筆，舊版流程無法處理',
    'DETAIL_ITEM_LIST_TRUNCATED_TO_100' => '官方明細超過 100 項，已讀取前 100 項；其餘可於正式交易補充',
    'DETAIL_ITEM_TABLE_RELOAD_TIMEOUT' => '已送出每頁 100 筆切換，但官方品項表未在 30 秒內完成更新',
    'DETAIL_ITEM_COUNT_MISMATCH' => '官方合計項目數與實際解析品項數不一致',
    'DETAIL_ITEM_ROW_PARSE_FAILED' => '消費明細列無法解析',
    'DETAIL_TOTAL_INTERNAL_MISMATCH' => '品項合計與官方總額不一致',
    'DETAIL_OFFICIAL_TAX_MISMATCH' => '官方稅額無法精確補足品項與總額差額',
    'DETAIL_UNALLOCATED_DIFFERENCE' => '官方頁面未提供可辨識稅額，仍有未分配差額',
    'DETAIL_TOTAL_CSV_MISMATCH' => '官方總額與查詢／CSV 金額不一致',
    'DETAIL_UNSUPPORTED_PROFILE' => '官方明細版型尚未支援',
    'DETAIL_CANCELLED' => '使用者已取消後續處理',
    'DETAIL_CANCELLED_ACTIVE' => '取消時正在處理',
    'DETAIL_NOT_STARTED_AFTER_CANCEL' => '取消後尚未開始',
    'DETAIL_MISSING_TERMINAL_RESULT' => '未收到逐筆終態結果',
    'DETAIL_BATCH_TIMEOUT' => '批次超過安全執行上限',
    'DETAIL_LINK_NOT_FOUND' => '找不到發票明細連結',
    'DETAIL_LINK_CLICK_FAILED' => '無法開啟發票明細',
    'DETAIL_TIMESTAMP_NOT_FOUND' => '找不到官方精確日期時間',
    _ => code,
  };
}

Object? _decodeObject(Object? raw) {
  if (raw is String) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  return raw;
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
