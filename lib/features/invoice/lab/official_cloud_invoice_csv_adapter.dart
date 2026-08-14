import 'dart:convert';

import '../cloud_invoice_candidate.dart';

const List<String> officialCloudInvoiceCsvHeaders = <String>[
  '載具自訂名稱',
  '發票日期',
  '發票號碼',
  '發票金額',
  '發票狀態',
  '折讓',
  '賣方統一編號',
  '賣方名稱',
  '賣方地址',
  '買方統編',
  '消費明細_數量',
  '消費明細_單價',
  '消費明細_金額',
  '消費明細_品名',
];

enum OfficialCloudInvoiceCsvIssueCode {
  invalidHeader,
  malformedRow,
  repairedSellerNameComma,
  ignoredFooter,
  inconsistentInvoiceMetadata,
  unsupportedInvoiceStatus,
  maskedInvoiceNumber,
  invalidInvoiceNumber,
  invalidInvoiceDate,
  invalidDetailAmount,
  invalidQuantity,
  invalidUnitPrice,
  missingItemName,
  rowAmountMismatch,
  discountPresent,
  fractionalAmountCurrencyUnknown,
}

class OfficialCloudInvoiceCsvIssue {
  const OfficialCloudInvoiceCsvIssue({
    required this.code,
    required this.message,
    required this.isBlocking,
    this.lineNumber,
    this.invoiceKey,
  });

  final OfficialCloudInvoiceCsvIssueCode code;
  final String message;
  final bool isBlocking;
  final int? lineNumber;
  final String? invoiceKey;
}

class OfficialCloudInvoiceCsvInvoicePreview {
  const OfficialCloudInvoiceCsvInvoicePreview({
    required this.id,
    required this.carrierName,
    required this.invoiceStatus,
    required this.discountFlag,
    required this.sellerAddress,
    required this.buyerIdentifier,
    required this.detailRowCount,
    required this.issues,
    this.candidate,
  });

  final String id;
  final String carrierName;
  final String invoiceStatus;
  final String discountFlag;
  final String sellerAddress;
  final String buyerIdentifier;
  final int detailRowCount;
  final List<OfficialCloudInvoiceCsvIssue> issues;
  final CloudInvoiceCandidate? candidate;

  bool get isSupported =>
      candidate != null && !issues.any((issue) => issue.isBlocking);
  bool get isBlocked => !isSupported;
}

class OfficialCloudInvoiceCsvPreview {
  const OfficialCloudInvoiceCsvPreview({
    required this.invoices,
    required this.fileIssues,
    required this.detailRowCount,
    required this.repairedRowCount,
    required this.ignoredFooterCount,
    required this.earliestInvoiceDate,
    required this.latestInvoiceDate,
  });

  final List<OfficialCloudInvoiceCsvInvoicePreview> invoices;
  final List<OfficialCloudInvoiceCsvIssue> fileIssues;
  final int detailRowCount;
  final int repairedRowCount;
  final int ignoredFooterCount;
  final DateTime? earliestInvoiceDate;
  final DateTime? latestInvoiceDate;

  int get invoiceCount => invoices.length;
  int get supportedInvoiceCount =>
      invoices.where((invoice) => invoice.isSupported).length;
  int get blockedInvoiceCount =>
      invoices.where((invoice) => invoice.isBlocked).length;
  bool get isBlocked => fileIssues.any((issue) => issue.isBlocking);
  bool get canImport => !isBlocked && supportedInvoiceCount > 0;
  bool get canCreateFormalTransactionAutomatically => false;

  List<CloudInvoiceCandidate> importSelected(Set<String> invoiceIds) {
    if (isBlocked || invoiceIds.isEmpty) {
      return const <CloudInvoiceCandidate>[];
    }
    return List<CloudInvoiceCandidate>.unmodifiable(
      invoices
          .where(
            (invoice) =>
                invoiceIds.contains(invoice.id) && invoice.isSupported,
          )
          .map((invoice) => invoice.candidate!),
    );
  }

  List<CloudInvoiceCandidate> importAllSupported() {
    if (isBlocked) return const <CloudInvoiceCandidate>[];
    return List<CloudInvoiceCandidate>.unmodifiable(
      invoices
          .where((invoice) => invoice.isSupported)
          .map((invoice) => invoice.candidate!),
    );
  }

  List<CloudInvoiceCandidate> cancel() {
    return const <CloudInvoiceCandidate>[];
  }
}

class OfficialCloudInvoiceCsvAdapter {
  const OfficialCloudInvoiceCsvAdapter({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  OfficialCloudInvoiceCsvPreview createPreview(String csvText) {
    final normalizedText = csvText.startsWith('\ufeff')
        ? csvText.substring(1)
        : csvText;
    final lines = const LineSplitter().convert(normalizedText);
    if (lines.isEmpty) return _invalidHeaderPreview();

    final header = _parseCsvLine(lines.first);
    if (!_sameHeaders(header, officialCloudInvoiceCsvHeaders)) {
      return _invalidHeaderPreview();
    }

    final fileIssues = <OfficialCloudInvoiceCsvIssue>[];
    final groupedRows = <String, List<_OfficialCsvDetailRow>>{};
    var detailRowCount = 0;
    var repairedRowCount = 0;
    var ignoredFooterCount = 0;

    for (var index = 1; index < lines.length; index += 1) {
      final lineNumber = index + 1;
      final line = lines[index];
      if (line.trim().isEmpty) continue;

      var fields = _parseCsvLine(line);
      if (fields.length == 1 && _isKnownFooter(fields.single)) {
        ignoredFooterCount += 1;
        fileIssues.add(
          OfficialCloudInvoiceCsvIssue(
            code: OfficialCloudInvoiceCsvIssueCode.ignoredFooter,
            message: 'Official explanatory footer was ignored.',
            isBlocking: false,
            lineNumber: lineNumber,
          ),
        );
        continue;
      }

      if (fields.length > officialCloudInvoiceCsvHeaders.length) {
        final repaired = _repairSellerNameComma(fields);
        if (repaired != null) {
          fields = repaired;
          repairedRowCount += 1;
          fileIssues.add(
            OfficialCloudInvoiceCsvIssue(
              code:
                  OfficialCloudInvoiceCsvIssueCode.repairedSellerNameComma,
              message:
                  'Recovered an unquoted comma inside the seller name.',
              isBlocking: false,
              lineNumber: lineNumber,
            ),
          );
        }
      }

      if (fields.length != officialCloudInvoiceCsvHeaders.length) {
        fileIssues.add(
          OfficialCloudInvoiceCsvIssue(
            code: OfficialCloudInvoiceCsvIssueCode.malformedRow,
            message: 'CSV row does not contain the expected 14 fields.',
            isBlocking: true,
            lineNumber: lineNumber,
          ),
        );
        continue;
      }

      detailRowCount += 1;
      final detail = _OfficialCsvDetailRow(
        lineNumber: lineNumber,
        carrierName: fields[0].trim(),
        invoiceDate: fields[1].trim(),
        invoiceNumber: _normalizeInvoiceNumber(fields[2]),
        rowAmount: fields[3].trim(),
        invoiceStatus: fields[4].trim(),
        discountFlag: fields[5].trim(),
        sellerIdentifier: fields[6].trim(),
        sellerName: fields[7].trim(),
        sellerAddress: fields[8].trim(),
        buyerIdentifier: fields[9].trim(),
        quantity: fields[10].trim(),
        unitPrice: fields[11].trim(),
        detailAmount: fields[12].trim(),
        itemName: fields[13].trim(),
      );
      final key = _groupKey(detail);
      groupedRows.putIfAbsent(key, () => <_OfficialCsvDetailRow>[]).add(
            detail,
          );
    }

    final previews = <OfficialCloudInvoiceCsvInvoicePreview>[];
    DateTime? earliestDate;
    DateTime? latestDate;
    for (final entry in groupedRows.entries) {
      final preview = _buildInvoicePreview(entry.key, entry.value);
      previews.add(preview);
      final date = preview.candidate?.invoiceDate;
      if (date != null) {
        earliestDate = earliestDate == null || date.isBefore(earliestDate)
            ? date
            : earliestDate;
        latestDate = latestDate == null || date.isAfter(latestDate)
            ? date
            : latestDate;
      }
    }
    previews.sort((left, right) {
      final leftDate = left.candidate?.invoiceDate;
      final rightDate = right.candidate?.invoiceDate;
      if (leftDate == null && rightDate == null) {
        return left.id.compareTo(right.id);
      }
      if (leftDate == null) return 1;
      if (rightDate == null) return -1;
      final dateCompare = rightDate.compareTo(leftDate);
      return dateCompare != 0 ? dateCompare : left.id.compareTo(right.id);
    });

    return OfficialCloudInvoiceCsvPreview(
      invoices:
          List<OfficialCloudInvoiceCsvInvoicePreview>.unmodifiable(previews),
      fileIssues: List<OfficialCloudInvoiceCsvIssue>.unmodifiable(fileIssues),
      detailRowCount: detailRowCount,
      repairedRowCount: repairedRowCount,
      ignoredFooterCount: ignoredFooterCount,
      earliestInvoiceDate: earliestDate,
      latestInvoiceDate: latestDate,
    );
  }

  OfficialCloudInvoiceCsvInvoicePreview _buildInvoicePreview(
    String invoiceKey,
    List<_OfficialCsvDetailRow> rows,
  ) {
    final first = rows.first;
    final issues = <OfficialCloudInvoiceCsvIssue>[];
    final invoiceNumber = first.invoiceNumber;
    final invoiceDate = _parseDate(first.invoiceDate);

    if (!RegExp(r'^[A-Z]{2}\d{8}$').hasMatch(invoiceNumber)) {
      final isMasked = RegExp(r'^[A-Z]{2}\d{5}\*{3}$').hasMatch(
        invoiceNumber,
      );
      issues.add(
        OfficialCloudInvoiceCsvIssue(
          code: isMasked
              ? OfficialCloudInvoiceCsvIssueCode.maskedInvoiceNumber
              : OfficialCloudInvoiceCsvIssueCode.invalidInvoiceNumber,
          message: isMasked
              ? 'Donated or void invoice number is partially masked.'
              : 'Invoice number is invalid.',
          isBlocking: true,
          invoiceKey: invoiceKey,
        ),
      );
    }
    if (invoiceDate == null) {
      issues.add(
        OfficialCloudInvoiceCsvIssue(
          code: OfficialCloudInvoiceCsvIssueCode.invalidInvoiceDate,
          message: 'Invoice date is invalid.',
          isBlocking: true,
          invoiceKey: invoiceKey,
        ),
      );
    }
    if (first.invoiceStatus != '開立已確認') {
      issues.add(
        OfficialCloudInvoiceCsvIssue(
          code: OfficialCloudInvoiceCsvIssueCode.unsupportedInvoiceStatus,
          message: 'Only confirmed issued invoices are importable.',
          isBlocking: true,
          invoiceKey: invoiceKey,
        ),
      );
    }
    if (first.discountFlag == '是') {
      issues.add(
        OfficialCloudInvoiceCsvIssue(
          code: OfficialCloudInvoiceCsvIssueCode.discountPresent,
          message: 'The invoice contains an allowance and requires review.',
          isBlocking: false,
          invoiceKey: invoiceKey,
        ),
      );
    }

    for (final row in rows.skip(1)) {
      if (!_sameInvoiceMetadata(first, row)) {
        issues.add(
          OfficialCloudInvoiceCsvIssue(
            code:
                OfficialCloudInvoiceCsvIssueCode.inconsistentInvoiceMetadata,
            message: 'Rows grouped as one invoice contain conflicting metadata.',
            isBlocking: true,
            lineNumber: row.lineNumber,
            invoiceKey: invoiceKey,
          ),
        );
      }
    }

    final lineItems = <CloudInvoiceLineItem>[];
    var totalAmount = 0.0;
    for (final row in rows) {
      final detailAmount = _parseNumber(row.detailAmount);
      if (detailAmount == null) {
        issues.add(
          OfficialCloudInvoiceCsvIssue(
            code: OfficialCloudInvoiceCsvIssueCode.invalidDetailAmount,
            message: 'Detail amount is invalid.',
            isBlocking: true,
            lineNumber: row.lineNumber,
            invoiceKey: invoiceKey,
          ),
        );
        continue;
      }
      totalAmount += detailAmount;

      final rowAmount = _parseNumber(row.rowAmount);
      if (rowAmount != null && (rowAmount - detailAmount).abs() > 0.000001) {
        issues.add(
          OfficialCloudInvoiceCsvIssue(
            code: OfficialCloudInvoiceCsvIssueCode.rowAmountMismatch,
            message:
                'Invoice amount column does not match the detail amount column.',
            isBlocking: false,
            lineNumber: row.lineNumber,
            invoiceKey: invoiceKey,
          ),
        );
      }

      final quantity = _parseNumber(row.quantity);
      if (quantity == null || quantity <= 0) {
        issues.add(
          OfficialCloudInvoiceCsvIssue(
            code: OfficialCloudInvoiceCsvIssueCode.invalidQuantity,
            message: 'Detail quantity is invalid.',
            isBlocking: false,
            lineNumber: row.lineNumber,
            invoiceKey: invoiceKey,
          ),
        );
      }
      final unitPrice = _parseNumber(row.unitPrice);
      if (unitPrice == null) {
        issues.add(
          OfficialCloudInvoiceCsvIssue(
            code: OfficialCloudInvoiceCsvIssueCode.invalidUnitPrice,
            message: 'Detail unit price is invalid.',
            isBlocking: false,
            lineNumber: row.lineNumber,
            invoiceKey: invoiceKey,
          ),
        );
      }
      if (row.itemName.isEmpty) {
        issues.add(
          OfficialCloudInvoiceCsvIssue(
            code: OfficialCloudInvoiceCsvIssueCode.missingItemName,
            message: 'Detail item name is missing.',
            isBlocking: false,
            lineNumber: row.lineNumber,
            invoiceKey: invoiceKey,
          ),
        );
      } else {
        lineItems.add(
          CloudInvoiceLineItem(
            name: row.itemName,
            amount: detailAmount,
            quantity: quantity,
            unitPrice: unitPrice,
          ),
        );
      }
    }

    if (totalAmount <= 0) {
      issues.add(
        OfficialCloudInvoiceCsvIssue(
          code: OfficialCloudInvoiceCsvIssueCode.invalidDetailAmount,
          message: 'Grouped invoice total must be greater than zero.',
          isBlocking: true,
          invoiceKey: invoiceKey,
        ),
      );
    }
    if ((totalAmount - totalAmount.roundToDouble()).abs() > 0.000001) {
      issues.add(
        OfficialCloudInvoiceCsvIssue(
          code: OfficialCloudInvoiceCsvIssueCode
              .fractionalAmountCurrencyUnknown,
          message:
              'Fractional amount detected; currency must be confirmed by the user.',
          isBlocking: false,
          invoiceKey: invoiceKey,
        ),
      );
    }

    final hasBlockingIssue = issues.any((issue) => issue.isBlocking);
    final warnings = <CloudInvoiceCandidateWarning>[];
    if (first.sellerName.isEmpty) {
      warnings.add(CloudInvoiceCandidateWarning.missingSellerName);
    }
    if (lineItems.isEmpty) {
      warnings.add(CloudInvoiceCandidateWarning.missingLineItems);
    }
    if (issues.isNotEmpty) {
      warnings.add(CloudInvoiceCandidateWarning.partialPayload);
    }
    if (issues.any(
      (issue) =>
          issue.code ==
          OfficialCloudInvoiceCsvIssueCode.fractionalAmountCurrencyUnknown,
    )) {
      warnings.add(CloudInvoiceCandidateWarning.lowConfidence);
    }

    final candidate = hasBlockingIssue || invoiceDate == null
        ? null
        : CloudInvoiceCandidate(
            source: CloudInvoiceCandidateSource.privateCloudResearch,
            status: CloudInvoiceCandidateStatus.pending,
            invoiceNumber: invoiceNumber,
            invoiceDate: invoiceDate,
            sellerIdentifier: first.sellerIdentifier,
            sellerName: first.sellerName,
            totalAmount: totalAmount,
            taxAmount: null,
            buyerIdentifier:
                first.buyerIdentifier.isEmpty ? null : first.buyerIdentifier,
            carrierType: first.carrierName,
            carrierMaskedId: '',
            fetchedAt: _clock().toUtc(),
            lineItems: List<CloudInvoiceLineItem>.unmodifiable(lineItems),
            rawPayload: null,
            warnings:
                List<CloudInvoiceCandidateWarning>.unmodifiable(warnings),
          );

    return OfficialCloudInvoiceCsvInvoicePreview(
      id: invoiceKey,
      carrierName: first.carrierName,
      invoiceStatus: first.invoiceStatus,
      discountFlag: first.discountFlag,
      sellerAddress: first.sellerAddress,
      buyerIdentifier: first.buyerIdentifier,
      detailRowCount: rows.length,
      issues: List<OfficialCloudInvoiceCsvIssue>.unmodifiable(issues),
      candidate: candidate,
    );
  }

  OfficialCloudInvoiceCsvPreview _invalidHeaderPreview() {
    return const OfficialCloudInvoiceCsvPreview(
      invoices: <OfficialCloudInvoiceCsvInvoicePreview>[],
      fileIssues: <OfficialCloudInvoiceCsvIssue>[
        OfficialCloudInvoiceCsvIssue(
          code: OfficialCloudInvoiceCsvIssueCode.invalidHeader,
          message: 'CSV header does not match the official export format.',
          isBlocking: true,
        ),
      ],
      detailRowCount: 0,
      repairedRowCount: 0,
      ignoredFooterCount: 0,
      earliestInvoiceDate: null,
      latestInvoiceDate: null,
    );
  }

  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var index = 0; index < line.length; index += 1) {
      final character = line[index];
      if (character == '"') {
        if (inQuotes && index + 1 < line.length && line[index + 1] == '"') {
          buffer.write('"');
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (character == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(character);
      }
    }
    fields.add(buffer.toString());
    return fields;
  }

  List<String>? _repairSellerNameComma(List<String> fields) {
    if (fields.length <= officialCloudInvoiceCsvHeaders.length) return null;
    const prefixLength = 7;
    const fixedTailLength = 6;
    if (fields.length <= prefixLength + fixedTailLength) return null;
    final sellerNameParts = fields.sublist(
      prefixLength,
      fields.length - fixedTailLength,
    );
    final repaired = <String>[
      ...fields.take(prefixLength),
      sellerNameParts.join(',').trim(),
      ...fields.skip(fields.length - fixedTailLength),
    ];
    return repaired.length == officialCloudInvoiceCsvHeaders.length
        ? repaired
        : null;
  }

  bool _sameHeaders(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].trim() != right[index]) return false;
    }
    return true;
  }

  bool _sameInvoiceMetadata(
    _OfficialCsvDetailRow left,
    _OfficialCsvDetailRow right,
  ) {
    return left.carrierName == right.carrierName &&
        left.invoiceDate == right.invoiceDate &&
        left.invoiceNumber == right.invoiceNumber &&
        left.invoiceStatus == right.invoiceStatus &&
        left.discountFlag == right.discountFlag &&
        left.sellerIdentifier == right.sellerIdentifier &&
        left.sellerName == right.sellerName &&
        left.sellerAddress == right.sellerAddress &&
        left.buyerIdentifier == right.buyerIdentifier;
  }

  bool _isKnownFooter(String value) {
    final normalized = value.trim();
    return normalized.startsWith('捐贈或作廢之發票') ||
        normalized.startsWith('注意：本功能所下載之雲端發票明細檔案');
  }

  String _groupKey(_OfficialCsvDetailRow row) {
    return '${row.invoiceNumber}|${row.invoiceDate}|${row.sellerIdentifier}';
  }

  String _normalizeInvoiceNumber(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  }

  DateTime? _parseDate(String value) {
    final compact = value.trim().replaceAll(RegExp(r'[-/.]'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(compact)) return null;
    final year = int.tryParse(compact.substring(0, 4));
    final month = int.tryParse(compact.substring(4, 6));
    final day = int.tryParse(compact.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  double? _parseNumber(String value) {
    final normalized = value
        .trim()
        .replaceAll('NT\$', '')
        .replaceAll('TWD', '')
        .replaceAll('\$', '')
        .replaceAll('元', '')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'\s'), '');
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}

class _OfficialCsvDetailRow {
  const _OfficialCsvDetailRow({
    required this.lineNumber,
    required this.carrierName,
    required this.invoiceDate,
    required this.invoiceNumber,
    required this.rowAmount,
    required this.invoiceStatus,
    required this.discountFlag,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.sellerAddress,
    required this.buyerIdentifier,
    required this.quantity,
    required this.unitPrice,
    required this.detailAmount,
    required this.itemName,
  });

  final int lineNumber;
  final String carrierName;
  final String invoiceDate;
  final String invoiceNumber;
  final String rowAmount;
  final String invoiceStatus;
  final String discountFlag;
  final String sellerIdentifier;
  final String sellerName;
  final String sellerAddress;
  final String buyerIdentifier;
  final String quantity;
  final String unitPrice;
  final String detailAmount;
  final String itemName;
}
