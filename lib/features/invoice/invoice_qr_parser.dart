import 'invoice_import_staging.dart';
import 'manual_invoice_draft.dart';

enum InvoiceQrParseReviewStatus {
  ready,
  needsReview,
  blocked,
}

class InvoiceQrParseReviewStatusMetadata {
  const InvoiceQrParseReviewStatusMetadata({
    required this.label,
    required this.canStageCandidate,
    required this.requiresManualReview,
  });

  final String label;
  final bool canStageCandidate;
  final bool requiresManualReview;
}

extension InvoiceQrParseReviewStatusMetadataX on InvoiceQrParseReviewStatus {
  InvoiceQrParseReviewStatusMetadata get metadata {
    switch (this) {
      case InvoiceQrParseReviewStatus.ready:
        return const InvoiceQrParseReviewStatusMetadata(
          label: '可匯入',
          canStageCandidate: true,
          requiresManualReview: false,
        );
      case InvoiceQrParseReviewStatus.needsReview:
        return const InvoiceQrParseReviewStatusMetadata(
          label: '可匯入，需確認',
          canStageCandidate: true,
          requiresManualReview: true,
        );
      case InvoiceQrParseReviewStatus.blocked:
        return const InvoiceQrParseReviewStatusMetadata(
          label: '不可匯入',
          canStageCandidate: false,
          requiresManualReview: true,
        );
    }
  }
}

class InvoiceQrParseResult {
  const InvoiceQrParseResult({
    required this.rawPayload,
    required this.errors,
    required this.warnings,
    this.invoiceNumber,
    this.invoiceDate,
    this.randomCode,
    this.salesAmount,
    this.totalAmount,
    this.buyerIdentifier,
    this.sellerIdentifier,
  });

  final String rawPayload;
  final String? invoiceNumber;
  final DateTime? invoiceDate;
  final String? randomCode;
  final int? salesAmount;
  final int? totalAmount;
  final String? buyerIdentifier;
  final String? sellerIdentifier;
  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty && invoiceNumber != null && invoiceDate != null && totalAmount != null;
  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get canStageCandidate => reviewStatus.metadata.canStageCandidate;
  bool get requiresManualReview => reviewStatus.metadata.requiresManualReview;
  String get sourceLabel => 'QR Code 離線解析';
  String get reviewStatusLabel => reviewStatus.metadata.label;
  String get warningSummary => warnings.join('、');
  String get errorSummary => errors.join('、');

  InvoiceQrParseReviewStatus get reviewStatus {
    if (!isValid) return InvoiceQrParseReviewStatus.blocked;
    if (warnings.isNotEmpty) return InvoiceQrParseReviewStatus.needsReview;
    return InvoiceQrParseReviewStatus.ready;
  }

  ManualInvoiceDraft toManualInvoiceDraftCandidate({
    required String id,
    required String sellerName,
    String note = '',
    DateTime? now,
  }) {
    if (!isValid) {
      throw StateError('QR parse result is not ready for manual invoice draft candidate.');
    }
    final timestamp = now ?? DateTime.now().toUtc();
    final seller = _resolveSellerName(sellerName);
    return ManualInvoiceDraft(
      id: id,
      invoiceNumber: invoiceNumber!,
      invoiceDate: invoiceDate!,
      sellerName: seller,
      totalAmount: totalAmount!.toDouble(),
      note: note.trim(),
      status: ManualInvoiceDraftStatus.readyToReview,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  InvoiceImportStagingItem toStagingItemCandidate({
    required String id,
    String sellerName = '',
    String note = '',
    DateTime? now,
  }) {
    if (!canStageCandidate) {
      throw StateError('QR parse result is not ready for invoice import staging.');
    }
    final timestamp = now ?? DateTime.now().toUtc();
    return InvoiceImportStagingItem(
      id: id,
      source: InvoiceImportStagingSource.qrParser,
      invoiceNumber: invoiceNumber!,
      invoiceDate: invoiceDate!,
      sellerName: _resolveSellerName(sellerName),
      totalAmount: totalAmount!.toDouble(),
      note: _buildStagingNote(note),
      rawPayload: rawPayload,
      status: InvoiceImportStagingStatus.pending,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  String _resolveSellerName(String sellerName) {
    final trimmed = sellerName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final sellerId = sellerIdentifier?.trim() ?? '';
    if (sellerId.isNotEmpty) return '賣方統編 $sellerId';
    return '未命名 QR 商家';
  }

  String _buildStagingNote(String note) {
    final parts = <String>[];
    final trimmed = note.trim();
    if (trimmed.isNotEmpty) parts.add(trimmed);
    if (hasWarnings) parts.add('QR 警示：$warningSummary');
    return parts.join('｜');
  }
}

class InvoiceQrParser {
  const InvoiceQrParser();

  static const int _minimumLeftQrLength = 77;

  InvoiceQrParseResult parse(String rawPayload) {
    final payload = rawPayload.trim();
    if (payload.isEmpty) {
      return const InvoiceQrParseResult(
        rawPayload: '',
        errors: <String>['QR payload 不可為空'],
        warnings: <String>[],
      );
    }
    if (payload.startsWith('**')) {
      return InvoiceQrParseResult(
        rawPayload: payload,
        errors: const <String>['目前 POC 僅支援電子發票左方 QR 基本資料，不支援右方明細 QR'],
        warnings: const <String>[],
      );
    }
    if (payload.length < _minimumLeftQrLength) {
      return InvoiceQrParseResult(
        rawPayload: payload,
        errors: const <String>['QR payload 長度不足，無法解析電子發票左方 QR 基本資料'],
        warnings: const <String>[],
      );
    }

    final fixed = payload.substring(0, _minimumLeftQrLength);
    final invoiceNumber = fixed.substring(0, 10).toUpperCase();
    final dateText = fixed.substring(10, 17);
    final randomCode = fixed.substring(17, 21);
    final salesAmountText = fixed.substring(21, 29);
    final totalAmountText = fixed.substring(29, 37);
    final buyerIdentifier = fixed.substring(37, 45);
    final sellerIdentifier = fixed.substring(45, 53);
    final encryptedCheck = fixed.substring(53, 77);

    final errors = <String>[];
    final warnings = <String>[];
    if (!RegExp(r'^[A-Z]{2}\d{8}$').hasMatch(invoiceNumber)) {
      errors.add('發票號碼格式不符合電子發票 QR 基本資料');
    }
    final invoiceDate = _parseRocDate(dateText);
    if (invoiceDate == null) errors.add('發票日期格式無法解析');
    final salesAmount = _parseHexAmount(salesAmountText);
    if (salesAmount == null) errors.add('銷售額無法解析');
    final totalAmount = _parseHexAmount(totalAmountText);
    if (totalAmount == null) errors.add('總額無法解析');
    if (!_isIdentifierOrZeros(buyerIdentifier)) warnings.add('買方統編格式非 8 碼數字，請人工確認');
    if (!_isIdentifierOrZeros(sellerIdentifier)) warnings.add('賣方統編格式非 8 碼數字，請人工確認');
    if (encryptedCheck.length != 24) warnings.add('加密驗證資訊長度非預期，請人工確認');
    if (payload.length > _minimumLeftQrLength) warnings.add('QR payload 含延伸明細，本階段僅解析前段基本資料');

    return InvoiceQrParseResult(
      rawPayload: payload,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      randomCode: randomCode,
      salesAmount: salesAmount,
      totalAmount: totalAmount,
      buyerIdentifier: buyerIdentifier,
      sellerIdentifier: sellerIdentifier,
      errors: List<String>.unmodifiable(errors),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static DateTime? _parseRocDate(String value) {
    if (!RegExp(r'^\d{7}$').hasMatch(value)) return null;
    final rocYear = int.tryParse(value.substring(0, 3));
    final month = int.tryParse(value.substring(3, 5));
    final day = int.tryParse(value.substring(5, 7));
    if (rocYear == null || month == null || day == null) return null;
    final date = DateTime(rocYear + 1911, month, day);
    if (date.month != month || date.day != day) return null;
    return DateTime(date.year, date.month, date.day);
  }

  static int? _parseHexAmount(String value) {
    if (!RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(value)) return null;
    return int.tryParse(value, radix: 16);
  }

  static bool _isIdentifierOrZeros(String value) {
    return RegExp(r'^\d{8}$').hasMatch(value);
  }
}
