import '../cloud_invoice_candidate.dart';

const String labInvoiceTableSchemaV1 = 'cloud_invoice_table.v1';

enum LabInvoiceTableIssueCode {
  unsupportedSchema,
  duplicateRowId,
  invalidInvoiceNumber,
  invalidInvoiceDate,
  invalidInvoiceTime,
  invalidTotalAmount,
  invalidTaxAmount,
  invalidSellerIdentifier,
  missingSellerName,
  missingLineItems,
  partialLineItems,
  duplicateWithinBatch,
}

class LabInvoiceTableIssue {
  const LabInvoiceTableIssue({
    required this.code,
    required this.message,
    required this.isBlocking,
  });

  final LabInvoiceTableIssueCode code;
  final String message;
  final bool isBlocking;
}

class LabInvoiceTableLineItemInput {
  const LabInvoiceTableLineItemInput({
    required this.name,
    required this.amount,
    this.quantity = '',
    this.unitPrice = '',
  });

  final String name;
  final String amount;
  final String quantity;
  final String unitPrice;
}

class LabInvoiceTableRowInput {
  const LabInvoiceTableRowInput({
    required this.rowId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    this.invoiceTime = '',
    this.sellerIdentifier = '',
    this.sellerName = '',
    this.taxAmount = '',
    this.carrierType = '',
    this.carrierDisplay = '',
    this.lineItems = const <LabInvoiceTableLineItemInput>[],
  });

  final String rowId;
  final String invoiceNumber;
  final String invoiceDate;
  final String invoiceTime;
  final String sellerIdentifier;
  final String sellerName;
  final String totalAmount;
  final String taxAmount;
  final String carrierType;
  final String carrierDisplay;
  final List<LabInvoiceTableLineItemInput> lineItems;
}

class LabInvoiceTableSelection {
  const LabInvoiceTableSelection({
    required this.schemaId,
    required this.rows,
  });

  final String schemaId;
  final List<LabInvoiceTableRowInput> rows;
}

enum LabInvoiceTableRowDisposition {
  supported,
  blocked,
}

class LabInvoiceTableRowPreview {
  const LabInvoiceTableRowPreview({
    required this.rowId,
    required this.disposition,
    required this.issues,
    this.candidate,
    this.duplicateOfRowId,
  });

  final String rowId;
  final LabInvoiceTableRowDisposition disposition;
  final List<LabInvoiceTableIssue> issues;
  final CloudInvoiceCandidate? candidate;
  final String? duplicateOfRowId;

  bool get isSupported =>
      disposition == LabInvoiceTableRowDisposition.supported &&
      candidate != null;
  bool get isBlocked => disposition == LabInvoiceTableRowDisposition.blocked;
}

class LabInvoiceTableExtractionPreview {
  const LabInvoiceTableExtractionPreview({
    required this.schemaId,
    required this.rows,
    required this.globalIssues,
  });

  final String schemaId;
  final List<LabInvoiceTableRowPreview> rows;
  final List<LabInvoiceTableIssue> globalIssues;

  int get detectedRowCount => rows.length;
  int get supportedRowCount => rows.where((row) => row.isSupported).length;
  int get blockedRowCount => rows.where((row) => row.isBlocked).length;
  int get duplicateHintCount => rows
      .where((row) => row.duplicateOfRowId != null)
      .length;
  bool get isBlocked => globalIssues.any((issue) => issue.isBlocking);
  bool get canImport => !isBlocked && supportedRowCount > 0;
  bool get canCreateFormalTransactionAutomatically => false;

  List<CloudInvoiceCandidate> importSelected(Set<String> rowIds) {
    if (isBlocked || rowIds.isEmpty) {
      return const <CloudInvoiceCandidate>[];
    }
    return List<CloudInvoiceCandidate>.unmodifiable(
      rows
          .where((row) => rowIds.contains(row.rowId) && row.isSupported)
          .map((row) => row.candidate!),
    );
  }

  List<CloudInvoiceCandidate> importAllSupported() {
    if (isBlocked) return const <CloudInvoiceCandidate>[];
    return List<CloudInvoiceCandidate>.unmodifiable(
      rows.where((row) => row.isSupported).map((row) => row.candidate!),
    );
  }

  List<CloudInvoiceCandidate> cancel() {
    return const <CloudInvoiceCandidate>[];
  }
}

class LabInvoiceTableExtractionAdapter {
  const LabInvoiceTableExtractionAdapter({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  LabInvoiceTableExtractionPreview createPreview(
    LabInvoiceTableSelection selection,
  ) {
    if (selection.schemaId != labInvoiceTableSchemaV1) {
      return LabInvoiceTableExtractionPreview(
        schemaId: selection.schemaId,
        rows: List<LabInvoiceTableRowPreview>.unmodifiable(
          selection.rows.map(
            (row) => LabInvoiceTableRowPreview(
              rowId: row.rowId.trim(),
              disposition: LabInvoiceTableRowDisposition.blocked,
              issues: const <LabInvoiceTableIssue>[
                LabInvoiceTableIssue(
                  code: LabInvoiceTableIssueCode.unsupportedSchema,
                  message: 'Unsupported invoice table schema.',
                  isBlocking: true,
                ),
              ],
            ),
          ),
        ),
        globalIssues: const <LabInvoiceTableIssue>[
          LabInvoiceTableIssue(
            code: LabInvoiceTableIssueCode.unsupportedSchema,
            message: 'The selected table does not match the approved schema.',
            isBlocking: true,
          ),
        ],
      );
    }

    final seenRowIds = <String>{};
    final firstRowByDuplicateKey = <String, String>{};
    final previews = <LabInvoiceTableRowPreview>[];

    for (final row in selection.rows) {
      final rowId = row.rowId.trim();
      if (rowId.isEmpty || !seenRowIds.add(rowId)) {
        previews.add(
          LabInvoiceTableRowPreview(
            rowId: rowId,
            disposition: LabInvoiceTableRowDisposition.blocked,
            issues: const <LabInvoiceTableIssue>[
              LabInvoiceTableIssue(
                code: LabInvoiceTableIssueCode.duplicateRowId,
                message: 'Row identifier is missing or duplicated.',
                isBlocking: true,
              ),
            ],
          ),
        );
        continue;
      }

      final preview = _normalizeRow(rowId: rowId, row: row);
      final candidate = preview.candidate;
      if (!preview.isSupported || candidate == null) {
        previews.add(preview);
        continue;
      }

      final firstRowId = firstRowByDuplicateKey[candidate.duplicateKey];
      if (firstRowId == null) {
        firstRowByDuplicateKey[candidate.duplicateKey] = rowId;
        previews.add(preview);
        continue;
      }

      previews.add(
        LabInvoiceTableRowPreview(
          rowId: rowId,
          disposition: LabInvoiceTableRowDisposition.supported,
          candidate: candidate.copyWith(
            status: CloudInvoiceCandidateStatus.duplicate,
          ),
          duplicateOfRowId: firstRowId,
          issues: List<LabInvoiceTableIssue>.unmodifiable(
            <LabInvoiceTableIssue>[
              ...preview.issues,
              const LabInvoiceTableIssue(
                code: LabInvoiceTableIssueCode.duplicateWithinBatch,
                message: 'Possible duplicate within the selected table.',
                isBlocking: false,
              ),
            ],
          ),
        ),
      );
    }

    return LabInvoiceTableExtractionPreview(
      schemaId: selection.schemaId,
      rows: List<LabInvoiceTableRowPreview>.unmodifiable(previews),
      globalIssues: const <LabInvoiceTableIssue>[],
    );
  }

  LabInvoiceTableRowPreview _normalizeRow({
    required String rowId,
    required LabInvoiceTableRowInput row,
  }) {
    final issues = <LabInvoiceTableIssue>[];
    final invoiceNumber = _normalizeInvoiceNumber(row.invoiceNumber);
    final date = _parseDate(row.invoiceDate);
    final time = _parseTime(row.invoiceTime);
    final totalAmount = _parseAmount(row.totalAmount);
    final taxAmount = row.taxAmount.trim().isEmpty
        ? null
        : _parseAmount(row.taxAmount);
    final sellerIdentifier = _normalizeSellerIdentifier(
      row.sellerIdentifier,
    );

    if (!RegExp(r'^[A-Z]{2}\d{8}$').hasMatch(invoiceNumber)) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.invalidInvoiceNumber,
          message: 'Invoice number must contain two letters and eight digits.',
          isBlocking: true,
        ),
      );
    }
    if (date == null) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.invalidInvoiceDate,
          message: 'Invoice date is missing or invalid.',
          isBlocking: true,
        ),
      );
    }
    if (row.invoiceTime.trim().isNotEmpty && time == null) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.invalidInvoiceTime,
          message: 'Invoice time is invalid.',
          isBlocking: true,
        ),
      );
    }
    if (totalAmount == null || totalAmount <= 0) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.invalidTotalAmount,
          message: 'Total amount must be a positive number.',
          isBlocking: true,
        ),
      );
    }
    if (row.taxAmount.trim().isNotEmpty &&
        (taxAmount == null || taxAmount < 0)) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.invalidTaxAmount,
          message: 'Tax amount is invalid.',
          isBlocking: true,
        ),
      );
    }
    if (sellerIdentifier.isNotEmpty &&
        !RegExp(r'^\d{8}$').hasMatch(sellerIdentifier)) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.invalidSellerIdentifier,
          message: 'Seller identifier is incomplete or invalid.',
          isBlocking: false,
        ),
      );
    }

    final sellerName = row.sellerName.trim();
    if (sellerName.isEmpty) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.missingSellerName,
          message: 'Seller name is missing and requires review.',
          isBlocking: false,
        ),
      );
    }

    final normalizedItems = <CloudInvoiceLineItem>[];
    var invalidLineItemCount = 0;
    for (final input in row.lineItems) {
      final item = _normalizeLineItem(input);
      if (item == null) {
        invalidLineItemCount += 1;
      } else {
        normalizedItems.add(item);
      }
    }
    if (normalizedItems.isEmpty) {
      issues.add(
        const LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.missingLineItems,
          message: 'No usable line items were detected.',
          isBlocking: false,
        ),
      );
    }
    if (invalidLineItemCount > 0) {
      issues.add(
        LabInvoiceTableIssue(
          code: LabInvoiceTableIssueCode.partialLineItems,
          message: '$invalidLineItemCount line item(s) were ignored.',
          isBlocking: false,
        ),
      );
    }

    if (issues.any((issue) => issue.isBlocking) ||
        date == null ||
        totalAmount == null) {
      return LabInvoiceTableRowPreview(
        rowId: rowId,
        disposition: LabInvoiceTableRowDisposition.blocked,
        issues: List<LabInvoiceTableIssue>.unmodifiable(issues),
      );
    }

    final candidateWarnings = <CloudInvoiceCandidateWarning>[];
    if (sellerName.isEmpty) {
      candidateWarnings.add(CloudInvoiceCandidateWarning.missingSellerName);
    }
    if (normalizedItems.isEmpty) {
      candidateWarnings.add(CloudInvoiceCandidateWarning.missingLineItems);
    }
    if (issues.isNotEmpty) {
      candidateWarnings.add(CloudInvoiceCandidateWarning.partialPayload);
    }

    final invoiceDate = DateTime(
      date.year,
      date.month,
      date.day,
      time?.$1 ?? 0,
      time?.$2 ?? 0,
      time?.$3 ?? 0,
    );
    final candidate = CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      sellerIdentifier: sellerIdentifier,
      sellerName: sellerName,
      totalAmount: totalAmount,
      taxAmount: taxAmount,
      carrierType: row.carrierType.trim(),
      carrierMaskedId: _maskCarrier(row.carrierDisplay),
      fetchedAt: _clock().toUtc(),
      lineItems: List<CloudInvoiceLineItem>.unmodifiable(normalizedItems),
      rawPayload: null,
      warnings: List<CloudInvoiceCandidateWarning>.unmodifiable(
        candidateWarnings,
      ),
    );

    return LabInvoiceTableRowPreview(
      rowId: rowId,
      disposition: LabInvoiceTableRowDisposition.supported,
      candidate: candidate,
      issues: List<LabInvoiceTableIssue>.unmodifiable(issues),
    );
  }

  CloudInvoiceLineItem? _normalizeLineItem(
    LabInvoiceTableLineItemInput input,
  ) {
    final name = input.name.trim();
    final amount = _parseAmount(input.amount);
    if (name.isEmpty || amount == null || amount < 0) return null;

    final quantity = input.quantity.trim().isEmpty
        ? null
        : _parseAmount(input.quantity);
    final unitPrice = input.unitPrice.trim().isEmpty
        ? null
        : _parseAmount(input.unitPrice);
    if (input.quantity.trim().isNotEmpty &&
        (quantity == null || quantity <= 0)) {
      return null;
    }
    if (input.unitPrice.trim().isNotEmpty &&
        (unitPrice == null || unitPrice < 0)) {
      return null;
    }

    return CloudInvoiceLineItem(
      name: name,
      rawName: null,
      amount: amount,
      quantity: quantity,
      unitPrice: unitPrice,
    );
  }

  String _normalizeInvoiceNumber(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  }

  String _normalizeSellerIdentifier(String value) {
    return value.replaceAll(RegExp(r'\s'), '');
  }

  DateTime? _parseDate(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;

    final compact = input.replaceAll(RegExp(r'[-/.]'), '');
    int? year;
    int? month;
    int? day;
    if (RegExp(r'^\d{8}$').hasMatch(compact)) {
      year = int.tryParse(compact.substring(0, 4));
      month = int.tryParse(compact.substring(4, 6));
      day = int.tryParse(compact.substring(6, 8));
    } else if (RegExp(r'^\d{7}$').hasMatch(compact)) {
      final rocYear = int.tryParse(compact.substring(0, 3));
      year = rocYear == null ? null : rocYear + 1911;
      month = int.tryParse(compact.substring(3, 5));
      day = int.tryParse(compact.substring(5, 7));
    }
    if (year == null || month == null || day == null) return null;

    final result = DateTime(year, month, day);
    if (result.year != year || result.month != month || result.day != day) {
      return null;
    }
    return result;
  }

  (int, int, int)? _parseTime(String value) {
    final input = value.trim();
    if (input.isEmpty) return (0, 0, 0);
    final compact = input.replaceAll(':', '');
    if (!RegExp(r'^\d{4}(\d{2})?$').hasMatch(compact)) return null;

    final hour = int.tryParse(compact.substring(0, 2));
    final minute = int.tryParse(compact.substring(2, 4));
    final second = compact.length == 6
        ? int.tryParse(compact.substring(4, 6))
        : 0;
    if (hour == null || minute == null || second == null) return null;
    if (hour > 23 || minute > 59 || second > 59) return null;
    return (hour, minute, second);
  }

  double? _parseAmount(String value) {
    var input = value.trim();
    if (input.isEmpty) return null;
    input = input
        .replaceAll('NT\$', '')
        .replaceAll('TWD', '')
        .replaceAll('\$', '')
        .replaceAll('元', '')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'\s'), '');
    final parsed = double.tryParse(input);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  String _maskCarrier(String value) {
    final input = value.trim();
    if (input.isEmpty) return '';
    if (input.contains('*')) return input;
    final suffix = input.length <= 4 ? input : input.substring(input.length - 4);
    return '****$suffix';
  }
}
