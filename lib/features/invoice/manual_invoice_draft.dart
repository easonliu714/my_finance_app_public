enum ManualInvoiceDraftStatus {
  draft,
  readyToReview,
  readyToConfirm,
  confirmed,
  rejected,
  duplicate,
}

class ManualInvoiceDraft {
  const ManualInvoiceDraft({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.sellerName,
    required this.totalAmount,
    this.taxAmount,
    this.note = '',
    this.status = ManualInvoiceDraftStatus.draft,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String sellerName;
  final double totalAmount;
  final double? taxAmount;
  final String note;
  final ManualInvoiceDraftStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get duplicateKey {
    final normalizedInvoiceNumber = invoiceNumber.trim().toUpperCase();
    final normalizedSeller = sellerName.trim().toLowerCase();
    final roundedAmount = totalAmount.toStringAsFixed(0);
    return '$normalizedInvoiceNumber|${_dateKey(invoiceDate)}|$roundedAmount|$normalizedSeller';
  }

  bool get isReadyForReview {
    return invoiceNumber.trim().isNotEmpty && sellerName.trim().isNotEmpty && totalAmount > 0;
  }

  ManualInvoiceDraft copyWith({
    String? id,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? sellerName,
    double? totalAmount,
    double? taxAmount,
    bool clearTaxAmount = false,
    String? note,
    ManualInvoiceDraftStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ManualInvoiceDraft(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      sellerName: sellerName ?? this.sellerName,
      totalAmount: totalAmount ?? this.totalAmount,
      taxAmount: clearTaxAmount ? null : (taxAmount ?? this.taxAmount),
      note: note ?? this.note,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'invoice_number': invoiceNumber.trim().toUpperCase(),
      'invoice_date': _dateTimeKey(invoiceDate),
      'seller_name': sellerName.trim(),
      'total_amount': totalAmount,
      'tax_amount': taxAmount,
      'note': note.trim(),
      'status': status.name,
      'duplicate_key': duplicateKey,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static ManualInvoiceDraft fromMap(Map<String, Object?> map) {
    return ManualInvoiceDraft(
      id: map['id']?.toString() ?? '',
      invoiceNumber: map['invoice_number']?.toString() ?? '',
      invoiceDate: DateTime.tryParse(map['invoice_date']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      sellerName: map['seller_name']?.toString() ?? '',
      totalAmount: _readDouble(map['total_amount']),
      taxAmount: map['tax_amount'] == null ? null : _readDouble(map['tax_amount']),
      note: map['note']?.toString() ?? '',
      status: ManualInvoiceDraftStatus.values.firstWhere(
        (status) => status.name == map['status']?.toString(),
        orElse: () => ManualInvoiceDraftStatus.draft,
      ),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }

  static double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _dateKey(DateTime value) {
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }

  static String _dateTimeKey(DateTime value) => value.toIso8601String();
}

class ManualInvoiceTransactionDraft {
  const ManualInvoiceTransactionDraft({
    required this.invoiceDraftId,
    required this.occurredAt,
    required this.amount,
    required this.merchantName,
    required this.note,
  });

  final String invoiceDraftId;
  final DateTime occurredAt;
  final double amount;
  final String merchantName;
  final String note;
}
