import 'manual_invoice_draft.dart';

enum InvoiceImportStagingSource {
  manual,
  qrParser,
  externalSource,
}

enum InvoiceImportStagingStatus {
  pending,
  accepted,
  rejected,
  duplicate,
  converted,
}

class InvoiceImportStagingStatusMetadata {
  const InvoiceImportStagingStatusMetadata({
    required this.label,
    required this.requiresUserReview,
    required this.canConvertToDraft,
    required this.isTerminal,
  });

  final String label;
  final bool requiresUserReview;
  final bool canConvertToDraft;
  final bool isTerminal;
}

extension InvoiceImportStagingStatusMetadataX on InvoiceImportStagingStatus {
  InvoiceImportStagingStatusMetadata get metadata {
    switch (this) {
      case InvoiceImportStagingStatus.pending:
        return const InvoiceImportStagingStatusMetadata(
          label: '待確認',
          requiresUserReview: true,
          canConvertToDraft: false,
          isTerminal: false,
        );
      case InvoiceImportStagingStatus.accepted:
        return const InvoiceImportStagingStatusMetadata(
          label: '已接受',
          requiresUserReview: false,
          canConvertToDraft: true,
          isTerminal: false,
        );
      case InvoiceImportStagingStatus.rejected:
        return const InvoiceImportStagingStatusMetadata(
          label: '已退回',
          requiresUserReview: false,
          canConvertToDraft: false,
          isTerminal: false,
        );
      case InvoiceImportStagingStatus.duplicate:
        return const InvoiceImportStagingStatusMetadata(
          label: '疑似重複',
          requiresUserReview: true,
          canConvertToDraft: false,
          isTerminal: false,
        );
      case InvoiceImportStagingStatus.converted:
        return const InvoiceImportStagingStatusMetadata(
          label: '已轉草稿',
          requiresUserReview: false,
          canConvertToDraft: false,
          isTerminal: true,
        );
    }
  }

  Set<InvoiceImportStagingStatus> get allowedNextStatuses {
    switch (this) {
      case InvoiceImportStagingStatus.pending:
        return const <InvoiceImportStagingStatus>{
          InvoiceImportStagingStatus.accepted,
          InvoiceImportStagingStatus.rejected,
          InvoiceImportStagingStatus.duplicate,
        };
      case InvoiceImportStagingStatus.accepted:
        return const <InvoiceImportStagingStatus>{
          InvoiceImportStagingStatus.pending,
          InvoiceImportStagingStatus.rejected,
          InvoiceImportStagingStatus.converted,
        };
      case InvoiceImportStagingStatus.rejected:
        return const <InvoiceImportStagingStatus>{
          InvoiceImportStagingStatus.pending,
        };
      case InvoiceImportStagingStatus.duplicate:
        return const <InvoiceImportStagingStatus>{
          InvoiceImportStagingStatus.pending,
          InvoiceImportStagingStatus.accepted,
          InvoiceImportStagingStatus.rejected,
        };
      case InvoiceImportStagingStatus.converted:
        return const <InvoiceImportStagingStatus>{};
    }
  }

  bool canTransitionTo(InvoiceImportStagingStatus target) {
    if (target == this) return true;
    return allowedNextStatuses.contains(target);
  }
}

class InvoiceImportStagingTransitionError implements Exception {
  const InvoiceImportStagingTransitionError(this.message);

  final String message;

  @override
  String toString() => message;
}

class InvoiceImportStagingItem {
  const InvoiceImportStagingItem({
    required this.id,
    required this.source,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.sellerName,
    required this.totalAmount,
    this.taxAmount,
    this.note = '',
    this.rawPayload,
    this.status = InvoiceImportStagingStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final InvoiceImportStagingSource source;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String sellerName;
  final double totalAmount;
  final double? taxAmount;
  final String note;
  final String? rawPayload;
  final InvoiceImportStagingStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isConvertible => status.metadata.canConvertToDraft;
  bool get requiresUserReview => status.metadata.requiresUserReview;
  bool get isTerminal => status.metadata.isTerminal;
  String get statusLabel => status.metadata.label;
  Set<InvoiceImportStagingStatus> get allowedNextStatuses => status.allowedNextStatuses;
  bool canTransitionTo(InvoiceImportStagingStatus target) => status.canTransitionTo(target);

  String get duplicateKey {
    final normalizedInvoiceNumber = invoiceNumber.trim().toUpperCase();
    final normalizedSeller = sellerName.trim().toLowerCase();
    final roundedAmount = totalAmount.toStringAsFixed(0);
    return '$normalizedInvoiceNumber|${_dateKey(invoiceDate)}|$roundedAmount|$normalizedSeller';
  }

  InvoiceImportStagingItem copyWith({
    String? id,
    InvoiceImportStagingSource? source,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? sellerName,
    double? totalAmount,
    double? taxAmount,
    bool clearTaxAmount = false,
    String? note,
    String? rawPayload,
    bool clearRawPayload = false,
    InvoiceImportStagingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InvoiceImportStagingItem(
      id: id ?? this.id,
      source: source ?? this.source,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      sellerName: sellerName ?? this.sellerName,
      totalAmount: totalAmount ?? this.totalAmount,
      taxAmount: clearTaxAmount ? null : (taxAmount ?? this.taxAmount),
      note: note ?? this.note,
      rawPayload: clearRawPayload ? null : (rawPayload ?? this.rawPayload),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  ManualInvoiceDraft toManualInvoiceDraftCandidate({
    required String id,
    DateTime? now,
  }) {
    if (!isConvertible) {
      throw const InvoiceImportStagingTransitionError('Only accepted staging items can be converted to manual invoice drafts.');
    }
    final timestamp = now ?? DateTime.now().toUtc();
    return ManualInvoiceDraft(
      id: id,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      sellerName: sellerName,
      totalAmount: totalAmount,
      taxAmount: taxAmount,
      note: note,
      status: ManualInvoiceDraftStatus.readyToReview,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static String _dateKey(DateTime value) {
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }
}

class InvoiceImportStagingBatch {
  const InvoiceImportStagingBatch({required this.id, required this.items});

  final String id;
  final List<InvoiceImportStagingItem> items;

  int get pendingCount => items.where((item) => item.status == InvoiceImportStagingStatus.pending).length;
  int get acceptedCount => items.where((item) => item.status == InvoiceImportStagingStatus.accepted).length;
  int get rejectedCount => items.where((item) => item.status == InvoiceImportStagingStatus.rejected).length;
  int get duplicateCount => items.where((item) => item.status == InvoiceImportStagingStatus.duplicate).length;
  int get convertedCount => items.where((item) => item.status == InvoiceImportStagingStatus.converted).length;

  Map<InvoiceImportStagingStatus, int> get statusCounts {
    return <InvoiceImportStagingStatus, int>{
      for (final status in InvoiceImportStagingStatus.values) status: items.where((item) => item.status == status).length,
    };
  }
}

class InvoiceImportStagingService {
  const InvoiceImportStagingService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  InvoiceImportStagingBatch createBatch({
    required String id,
    required List<InvoiceImportStagingItem> items,
  }) {
    final seenKeys = <String>{};
    final now = _clock().toUtc();
    final stagedItems = <InvoiceImportStagingItem>[];
    for (final item in items) {
      final isDuplicate = !seenKeys.add(item.duplicateKey);
      final shouldMarkDuplicate = isDuplicate && item.status == InvoiceImportStagingStatus.pending;
      stagedItems.add(
        item.copyWith(
          status: shouldMarkDuplicate ? InvoiceImportStagingStatus.duplicate : item.status,
          createdAt: item.createdAt ?? now,
          updatedAt: now,
        ),
      );
    }
    return InvoiceImportStagingBatch(id: id, items: List<InvoiceImportStagingItem>.unmodifiable(stagedItems));
  }

  InvoiceImportStagingItem updateStatus({
    required InvoiceImportStagingItem item,
    required InvoiceImportStagingStatus status,
  }) {
    if (!item.canTransitionTo(status)) {
      throw InvoiceImportStagingTransitionError('Invalid staging status transition: ${item.status.name} -> ${status.name}.');
    }
    return item.copyWith(status: status, updatedAt: _clock().toUtc());
  }

  InvoiceImportStagingItem acceptItem(InvoiceImportStagingItem item) {
    return updateStatus(item: item, status: InvoiceImportStagingStatus.accepted);
  }

  InvoiceImportStagingItem rejectItem(InvoiceImportStagingItem item) {
    return updateStatus(item: item, status: InvoiceImportStagingStatus.rejected);
  }

  InvoiceImportStagingItem markDuplicate(InvoiceImportStagingItem item) {
    return updateStatus(item: item, status: InvoiceImportStagingStatus.duplicate);
  }

  InvoiceImportStagingItem markConverted(InvoiceImportStagingItem item) {
    return updateStatus(item: item, status: InvoiceImportStagingStatus.converted);
  }

  ManualInvoiceDraft convertAcceptedItem({
    required InvoiceImportStagingItem item,
    required String draftId,
  }) {
    return item.toManualInvoiceDraftCandidate(id: draftId, now: _clock().toUtc());
  }
}
