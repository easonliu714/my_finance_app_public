import 'official_invoice_detail_enrichment.dart';

enum OfficialInvoiceDetailResidualCategory {
  successful,
  estimatedTaxConfirmation,
  technicalRetryable,
  sourceContentIncomplete,
  identityOrTotalConflict,
  failClosedOther,
}

extension OfficialInvoiceDetailResidualCategoryLabel
    on OfficialInvoiceDetailResidualCategory {
  String get label => switch (this) {
        OfficialInvoiceDetailResidualCategory.successful => '成功',
        OfficialInvoiceDetailResidualCategory.estimatedTaxConfirmation =>
          '可確認推算稅額',
        OfficialInvoiceDetailResidualCategory.technicalRetryable =>
          '技術性可重試',
        OfficialInvoiceDetailResidualCategory.sourceContentIncomplete =>
          '來源內容不足',
        OfficialInvoiceDetailResidualCategory.identityOrTotalConflict =>
          '身分／總額衝突',
        OfficialInvoiceDetailResidualCategory.failClosedOther =>
          '其他需覆核',
      };
}

class OfficialInvoiceDetailResidualItem {
  const OfficialInvoiceDetailResidualItem({
    required this.ordinal,
    required this.invoiceNumber,
    required this.reasonCode,
    required this.category,
    required this.hasDuplicateInvoiceNumber,
    this.enrichment,
    this.trace,
  });

  final int ordinal;
  final String invoiceNumber;
  final String reasonCode;
  final OfficialInvoiceDetailResidualCategory category;
  final bool hasDuplicateInvoiceNumber;
  final OfficialInvoiceDetailEnrichment? enrichment;
  final OfficialInvoiceDetailTraceItem? trace;

  bool get retryEligible =>
      category == OfficialInvoiceDetailResidualCategory.technicalRetryable &&
      !hasDuplicateInvoiceNumber;

  String? get retryBlockedReason {
    if (category != OfficialInvoiceDetailResidualCategory.technicalRetryable) {
      return '此結果必須人工覆核，不可自動重試。';
    }
    if (hasDuplicateInvoiceNumber) {
      return '同批次存在相同發票號碼；為避免覆蓋其他 ordinal，禁止直接重試。';
    }
    return null;
  }
}

class OfficialInvoiceDetailRetryOutcome {
  const OfficialInvoiceDetailRetryOutcome({
    required this.originalOrdinal,
    required this.invoiceNumber,
    required this.retryBatchResult,
  });

  final int originalOrdinal;
  final String invoiceNumber;
  final OfficialInvoiceDetailBatchResult retryBatchResult;

  OfficialInvoiceDetailEnrichment? get enrichment {
    final normalized = _normalizeInvoiceNumber(invoiceNumber);
    for (final item in retryBatchResult.results) {
      if (_normalizeInvoiceNumber(_invoiceNumberOf(item)) == normalized) {
        return item;
      }
    }
    return retryBatchResult.results.length == 1
        ? retryBatchResult.results.single
        : null;
  }

  OfficialInvoiceDetailTraceItem? get terminalTrace {
    final terminal = retryBatchResult.traces
        .where((item) => item.isTerminal)
        .toList(growable: false);
    return terminal.isEmpty ? null : terminal.last;
  }
}

OfficialInvoiceDetailResidualCategory
    officialInvoiceDetailResidualCategoryForEnrichment(
  OfficialInvoiceDetailEnrichment item,
) {
  if (item.success) return OfficialInvoiceDetailResidualCategory.successful;
  if (item.canUseUserConfirmedEstimatedTax) {
    return OfficialInvoiceDetailResidualCategory.estimatedTaxConfirmation;
  }
  return officialInvoiceDetailResidualCategoryForCode(
    item.errorCode ?? 'DETAIL_UNKNOWN_FAILURE',
  );
}

OfficialInvoiceDetailResidualCategory
    officialInvoiceDetailResidualCategoryForCode(String code) {
  if (_technicalRetryableCodes.contains(code)) {
    return OfficialInvoiceDetailResidualCategory.technicalRetryable;
  }
  if (_identityOrTotalConflictCodes.contains(code)) {
    return OfficialInvoiceDetailResidualCategory.identityOrTotalConflict;
  }
  if (_sourceContentIncompleteCodes.contains(code)) {
    return OfficialInvoiceDetailResidualCategory.sourceContentIncomplete;
  }
  return OfficialInvoiceDetailResidualCategory.failClosedOther;
}

String officialInvoiceDetailResidualReasonLabel(String code) {
  return switch (code) {
    'DETAIL_RETRY_EXECUTION_FAILED' => '前景重試執行失敗',
    'DETAIL_RETRY_DUPLICATE_IDENTITY_BLOCKED' =>
      '同批次發票號碼重複，已禁止自動重試',
    _ => officialInvoiceDetailFailureLabel(code),
  };
}

extension OfficialInvoiceDetailBatchRetryDiagnostics
    on OfficialInvoiceDetailBatchResult {
  List<OfficialInvoiceDetailResidualItem> get residualItems {
    final resultIndexByOrdinal = _resultIndexByOrdinal(this);
    final usedResultIndexes = resultIndexByOrdinal.values.toSet();
    final duplicateCounts = <String, int>{};
    for (final trace in traces) {
      final normalized = _normalizeInvoiceNumber(trace.invoiceNumber);
      duplicateCounts[normalized] = (duplicateCounts[normalized] ?? 0) + 1;
    }

    final output = <OfficialInvoiceDetailResidualItem>[];
    final sortedTraces = traces.toList(growable: false)
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    for (final trace in sortedTraces) {
      final resultIndex = resultIndexByOrdinal[trace.ordinal];
      final enrichment = resultIndex == null ? null : results[resultIndex];
      if (enrichment?.success == true ||
          (enrichment == null &&
              trace.status == OfficialInvoiceDetailTraceStatus.success)) {
        continue;
      }
      final reasonCode = enrichment?.errorCode ??
          trace.reasonCode ??
          _reasonCodeForTraceStatus(trace.status);
      final category = enrichment == null
          ? officialInvoiceDetailResidualCategoryForCode(reasonCode)
          : officialInvoiceDetailResidualCategoryForEnrichment(enrichment);
      final invoiceNumber = trace.invoiceNumber.isNotEmpty
          ? trace.invoiceNumber
          : enrichment == null
              ? ''
              : _invoiceNumberOf(enrichment);
      output.add(
        OfficialInvoiceDetailResidualItem(
          ordinal: trace.ordinal,
          invoiceNumber: invoiceNumber,
          reasonCode: reasonCode,
          category: category,
          hasDuplicateInvoiceNumber:
              (duplicateCounts[_normalizeInvoiceNumber(invoiceNumber)] ?? 0) >
                  1,
          enrichment: enrichment,
          trace: trace,
        ),
      );
    }

    var nextFallbackOrdinal = requestedCount + 1;
    for (var index = 0; index < results.length; index++) {
      if (usedResultIndexes.contains(index) || results[index].success) continue;
      final enrichment = results[index];
      final invoiceNumber = _invoiceNumberOf(enrichment);
      output.add(
        OfficialInvoiceDetailResidualItem(
          ordinal: nextFallbackOrdinal++,
          invoiceNumber: invoiceNumber,
          reasonCode: enrichment.errorCode ?? 'DETAIL_UNKNOWN_FAILURE',
          category:
              officialInvoiceDetailResidualCategoryForEnrichment(enrichment),
          hasDuplicateInvoiceNumber: false,
          enrichment: enrichment,
        ),
      );
    }

    output.sort((left, right) => left.ordinal.compareTo(right.ordinal));
    return List.unmodifiable(output);
  }

  int get estimatedTaxReviewCount => residualItems
      .where(
        (item) =>
            item.category ==
            OfficialInvoiceDetailResidualCategory.estimatedTaxConfirmation,
      )
      .length;

  int get technicalRetryableCount => residualItems
      .where(
        (item) =>
            item.category ==
            OfficialInvoiceDetailResidualCategory.technicalRetryable,
      )
      .length;

  int get safeRetryableCount =>
      residualItems.where((item) => item.retryEligible).length;

  int get sourceContentIncompleteCount => residualItems
      .where(
        (item) =>
            item.category ==
            OfficialInvoiceDetailResidualCategory.sourceContentIncomplete,
      )
      .length;

  int get identityOrTotalConflictCount => residualItems
      .where(
        (item) =>
            item.category ==
            OfficialInvoiceDetailResidualCategory.identityOrTotalConflict,
      )
      .length;

  int get otherFailClosedCount => residualItems
      .where(
        (item) =>
            item.category ==
            OfficialInvoiceDetailResidualCategory.failClosedOther,
      )
      .length;

  int get failClosedCount => sourceContentIncompleteCount +
      identityOrTotalConflictCount +
      otherFailClosedCount;

  OfficialInvoiceDetailBatchResult mergeRetryOutcomes(
    List<OfficialInvoiceDetailRetryOutcome> outcomes,
  ) {
    if (outcomes.isEmpty) return this;

    final originalIndexByOrdinal = _resultIndexByOrdinal(this);
    final originalMappedIndexes = originalIndexByOrdinal.values.toSet();
    final resultByOrdinal = <int, OfficialInvoiceDetailEnrichment>{
      for (final entry in originalIndexByOrdinal.entries)
        entry.key: results[entry.value],
    };
    final extraResults = <OfficialInvoiceDetailEnrichment>[
      for (var index = 0; index < results.length; index++)
        if (!originalMappedIndexes.contains(index)) results[index],
    ];
    final traceByOrdinal = <int, OfficialInvoiceDetailTraceItem>{
      for (final trace in traces) trace.ordinal: trace,
    };
    final residualByOrdinal = <int, OfficialInvoiceDetailResidualItem>{
      for (final residual in residualItems) residual.ordinal: residual,
    };

    String? latestBatchError;
    for (final outcome in outcomes) {
      final original = residualByOrdinal[outcome.originalOrdinal];
      if (original == null || !original.retryEligible) continue;
      if (_normalizeInvoiceNumber(original.invoiceNumber) !=
          _normalizeInvoiceNumber(outcome.invoiceNumber)) {
        continue;
      }

      final enrichment = outcome.enrichment;
      if (enrichment != null &&
          _normalizeInvoiceNumber(_invoiceNumberOf(enrichment)) ==
              _normalizeInvoiceNumber(original.invoiceNumber)) {
        resultByOrdinal[original.ordinal] = enrichment;
      }

      final retryTrace = outcome.terminalTrace;
      if (retryTrace != null) {
        traceByOrdinal[original.ordinal] = OfficialInvoiceDetailTraceItem(
          invoiceNumber: original.invoiceNumber,
          ordinal: original.ordinal,
          status: retryTrace.status,
          startedAt: retryTrace.startedAt,
          completedAt: retryTrace.completedAt,
          reasonCode: retryTrace.reasonCode,
        );
      } else if (enrichment != null) {
        traceByOrdinal[original.ordinal] = OfficialInvoiceDetailTraceItem(
          invoiceNumber: original.invoiceNumber,
          ordinal: original.ordinal,
          status: enrichment.success
              ? OfficialInvoiceDetailTraceStatus.success
              : officialInvoiceDetailResidualCategoryForEnrichment(enrichment) ==
                      OfficialInvoiceDetailResidualCategory.technicalRetryable
                  ? OfficialInvoiceDetailTraceStatus.failed
                  : OfficialInvoiceDetailTraceStatus.review,
          completedAt: enrichment.fetchedAt,
          reasonCode: enrichment.errorCode,
        );
      }
      latestBatchError = outcome.retryBatchResult.errorCode ?? latestBatchError;
    }

    final sortedOrdinals = resultByOrdinal.keys.toList(growable: false)..sort();
    final mergedResults = <OfficialInvoiceDetailEnrichment>[
      for (final ordinal in sortedOrdinals) resultByOrdinal[ordinal]!,
      ...extraResults,
    ];
    final mergedTraces = traceByOrdinal.values.toList(growable: false)
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    final stillCancelled = mergedTraces.any(
      (trace) =>
          trace.status == OfficialInvoiceDetailTraceStatus.cancelledActive ||
          trace.status ==
              OfficialInvoiceDetailTraceStatus.notStartedAfterCancel,
    );

    return OfficialInvoiceDetailBatchResult(
      requestedCount: requestedCount,
      results: List.unmodifiable(mergedResults),
      cancelled: stillCancelled,
      traces: List.unmodifiable(mergedTraces),
      errorCode: latestBatchError ?? (stillCancelled ? errorCode : null),
    );
  }
}

Map<int, int> _resultIndexByOrdinal(
  OfficialInvoiceDetailBatchResult batch,
) {
  final output = <int, int>{};
  final used = <int>{};
  final sortedTraces = batch.traces.toList(growable: false)
    ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
  for (final trace in sortedTraces) {
    final normalized = _normalizeInvoiceNumber(trace.invoiceNumber);
    final index = batch.results.indexWhere(
      (item) =>
          !used.contains(batch.results.indexOf(item)) &&
          _normalizeInvoiceNumber(_invoiceNumberOf(item)) == normalized,
    );
    if (index < 0) continue;
    output[trace.ordinal] = index;
    used.add(index);
  }
  return output;
}

String _invoiceNumberOf(OfficialInvoiceDetailEnrichment item) {
  return item.invoiceNumber.isNotEmpty
      ? item.invoiceNumber
      : item.requestedInvoiceNumber;
}

String _normalizeInvoiceNumber(String value) => value.trim().toUpperCase();

String _reasonCodeForTraceStatus(OfficialInvoiceDetailTraceStatus status) {
  return switch (status) {
    OfficialInvoiceDetailTraceStatus.cancelledActive =>
      'DETAIL_CANCELLED_ACTIVE',
    OfficialInvoiceDetailTraceStatus.notStartedAfterCancel =>
      'DETAIL_NOT_STARTED_AFTER_CANCEL',
    OfficialInvoiceDetailTraceStatus.missingTerminalResult =>
      'DETAIL_MISSING_TERMINAL_RESULT',
    OfficialInvoiceDetailTraceStatus.failed => 'DETAIL_UNKNOWN_FAILURE',
    OfficialInvoiceDetailTraceStatus.review => 'DETAIL_UNKNOWN_FAILURE',
    OfficialInvoiceDetailTraceStatus.pending ||
    OfficialInvoiceDetailTraceStatus.running =>
      'DETAIL_MISSING_TERMINAL_RESULT',
    OfficialInvoiceDetailTraceStatus.success => 'DETAIL_UNKNOWN_FAILURE',
  };
}

const Set<String> _technicalRetryableCodes = <String>{
  'DETAIL_NO_DIALOG',
  'DETAIL_RENDER_TIMEOUT',
  'DETAIL_ITEM_TABLE_RELOAD_TIMEOUT',
  'DETAIL_ITEM_PAGE_SIZE_100_NOT_AVAILABLE',
  'DETAIL_ITEM_PAGE_SIZE_APPLY_NOT_TRIGGERED',
  'DETAIL_LINK_NOT_FOUND',
  'DETAIL_LINK_CLICK_FAILED',
  'DETAIL_SCRIPT_START_FAILED',
  'DETAIL_BATCH_FAILED',
  'DETAIL_BATCH_TIMEOUT',
  'DETAIL_CANCELLED',
  'DETAIL_CANCELLED_ACTIVE',
  'DETAIL_NOT_STARTED_AFTER_CANCEL',
  'DETAIL_MISSING_TERMINAL_RESULT',
  'DETAIL_SESSION_DISPOSED',
  'DETAIL_RETRY_EXECUTION_FAILED',
};

const Set<String> _sourceContentIncompleteCodes = <String>{
  'DETAIL_REQUIRED_FIELD_MISSING',
  'DETAIL_ITEM_TABLE_NOT_FOUND',
  'DETAIL_ITEM_ROW_PARSE_FAILED',
  'DETAIL_TIMESTAMP_NOT_FOUND',
  'DETAIL_UNSUPPORTED_PROFILE',
  'DETAIL_UNALLOCATED_DIFFERENCE',
  'DETAIL_RESULT_TABLE_NOT_FOUND',
  'DETAIL_SCOPE_EMPTY',
};

const Set<String> _identityOrTotalConflictCodes = <String>{
  'DETAIL_INVOICE_IDENTITY_MISMATCH',
  'DETAIL_TOTAL_INTERNAL_MISMATCH',
  'DETAIL_OFFICIAL_TAX_MISMATCH',
  'DETAIL_TOTAL_CSV_MISMATCH',
};
