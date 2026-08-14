class CloudInvoiceQueryCheckpoint {
  const CloudInvoiceQueryCheckpoint({
    this.lastSuccessfulQueryEndDate,
    this.latestImportedInvoiceDate,
    this.lastImportedInvoiceKey,
  });

  final DateTime? lastSuccessfulQueryEndDate;
  final DateTime? latestImportedInvoiceDate;
  final String? lastImportedInvoiceKey;

  DateTime? get preferredResumeDate =>
      lastSuccessfulQueryEndDate ?? latestImportedInvoiceDate;
}

enum CloudInvoiceQueryPlanIssueCode {
  initialStartDateRequired,
  invalidDateRange,
  resumeDateInFuture,
}

class CloudInvoiceQueryPlanIssue {
  const CloudInvoiceQueryPlanIssue({
    required this.code,
    required this.message,
    required this.isBlocking,
  });

  final CloudInvoiceQueryPlanIssueCode code;
  final String message;
  final bool isBlocking;
}

class CloudInvoiceQueryWindow {
  const CloudInvoiceQueryWindow({
    required this.startDate,
    required this.endDate,
  });

  final DateTime startDate;
  final DateTime endDate;

  bool get isSingleCalendarMonth =>
      startDate.year == endDate.year && startDate.month == endDate.month;

  int get inclusiveDayCount =>
      endDate.difference(startDate).inDays + 1;
}

class CloudInvoiceQueryPlan {
  const CloudInvoiceQueryPlan({
    required this.windows,
    required this.issues,
    required this.overlapDays,
    required this.usedCheckpoint,
  });

  final List<CloudInvoiceQueryWindow> windows;
  final List<CloudInvoiceQueryPlanIssue> issues;
  final int overlapDays;
  final bool usedCheckpoint;

  bool get isBlocked => issues.any((issue) => issue.isBlocking);
  bool get canRun => !isBlocked && windows.isNotEmpty;
  bool get requiresInitialStartDate => issues.any(
        (issue) =>
            issue.code ==
            CloudInvoiceQueryPlanIssueCode.initialStartDateRequired,
      );
}

class AuthenticatedCloudInvoiceQueryPlanner {
  const AuthenticatedCloudInvoiceQueryPlanner({
    this.overlapDays = 2,
  }) : assert(overlapDays >= 0);

  final int overlapDays;

  CloudInvoiceQueryPlan createPlan({
    required DateTime today,
    required CloudInvoiceQueryCheckpoint checkpoint,
    DateTime? initialStartDate,
    DateTime? allowedEarliestDate,
  }) {
    final normalizedToday = _dateOnly(today);
    final resumeDate = checkpoint.preferredResumeDate;
    if (resumeDate == null && initialStartDate == null) {
      return CloudInvoiceQueryPlan(
        windows: const <CloudInvoiceQueryWindow>[],
        issues: const <CloudInvoiceQueryPlanIssue>[
          CloudInvoiceQueryPlanIssue(
            code: CloudInvoiceQueryPlanIssueCode.initialStartDateRequired,
            message:
                'An initial start date is required when no prior import checkpoint exists.',
            isBlocking: true,
          ),
        ],
        overlapDays: overlapDays,
        usedCheckpoint: false,
      );
    }

    final normalizedResumeDate = resumeDate == null
        ? null
        : _dateOnly(resumeDate);
    if (normalizedResumeDate != null &&
        normalizedResumeDate.isAfter(normalizedToday)) {
      return CloudInvoiceQueryPlan(
        windows: const <CloudInvoiceQueryWindow>[],
        issues: const <CloudInvoiceQueryPlanIssue>[
          CloudInvoiceQueryPlanIssue(
            code: CloudInvoiceQueryPlanIssueCode.resumeDateInFuture,
            message: 'The saved query checkpoint is later than today.',
            isBlocking: true,
          ),
        ],
        overlapDays: overlapDays,
        usedCheckpoint: true,
      );
    }

    var startDate = normalizedResumeDate == null
        ? _dateOnly(initialStartDate!)
        : normalizedResumeDate.subtract(Duration(days: overlapDays));
    final earliestDate = allowedEarliestDate == null
        ? null
        : _dateOnly(allowedEarliestDate);
    if (earliestDate != null && startDate.isBefore(earliestDate)) {
      startDate = earliestDate;
    }

    if (startDate.isAfter(normalizedToday)) {
      return CloudInvoiceQueryPlan(
        windows: const <CloudInvoiceQueryWindow>[],
        issues: const <CloudInvoiceQueryPlanIssue>[
          CloudInvoiceQueryPlanIssue(
            code: CloudInvoiceQueryPlanIssueCode.invalidDateRange,
            message: 'The query start date cannot be later than today.',
            isBlocking: true,
          ),
        ],
        overlapDays: overlapDays,
        usedCheckpoint: normalizedResumeDate != null,
      );
    }

    final windows = <CloudInvoiceQueryWindow>[];
    var cursor = startDate;
    while (!cursor.isAfter(normalizedToday)) {
      final monthEnd = DateTime(cursor.year, cursor.month + 1, 0);
      final endDate = monthEnd.isBefore(normalizedToday)
          ? monthEnd
          : normalizedToday;
      windows.add(
        CloudInvoiceQueryWindow(
          startDate: cursor,
          endDate: endDate,
        ),
      );
      cursor = endDate.add(const Duration(days: 1));
    }

    return CloudInvoiceQueryPlan(
      windows: List<CloudInvoiceQueryWindow>.unmodifiable(windows),
      issues: const <CloudInvoiceQueryPlanIssue>[],
      overlapDays: overlapDays,
      usedCheckpoint: normalizedResumeDate != null,
    );
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

enum CloudInvoicePageSizeIssueCode {
  noSupportedPageSize,
}

class CloudInvoicePageSizeIssue {
  const CloudInvoicePageSizeIssue({
    required this.code,
    required this.message,
    required this.isBlocking,
  });

  final CloudInvoicePageSizeIssueCode code;
  final String message;
  final bool isBlocking;
}

class CloudInvoicePageSizePlan {
  const CloudInvoicePageSizePlan({
    required this.availablePageSizes,
    required this.selectedPageSize,
    required this.issues,
  });

  final List<int> availablePageSizes;
  final int? selectedPageSize;
  final List<CloudInvoicePageSizeIssue> issues;

  bool get canApply =>
      selectedPageSize != null && !issues.any((issue) => issue.isBlocking);
  bool get selectedPreferredHundred => selectedPageSize == 100;
}

class CloudInvoicePageSizePlanner {
  const CloudInvoicePageSizePlanner();

  CloudInvoicePageSizePlan createPlan(Iterable<int> pageSizes) {
    final normalized = pageSizes
        .where((value) => value > 0)
        .toSet()
        .toList()
      ..sort();
    if (normalized.isEmpty) {
      return const CloudInvoicePageSizePlan(
        availablePageSizes: <int>[],
        selectedPageSize: null,
        issues: <CloudInvoicePageSizeIssue>[
          CloudInvoicePageSizeIssue(
            code: CloudInvoicePageSizeIssueCode.noSupportedPageSize,
            message: 'The page does not expose a usable page-size option.',
            isBlocking: true,
          ),
        ],
      );
    }

    final selected = normalized.contains(100) ? 100 : normalized.last;
    return CloudInvoicePageSizePlan(
      availablePageSizes: List<int>.unmodifiable(normalized),
      selectedPageSize: selected,
      issues: const <CloudInvoicePageSizeIssue>[],
    );
  }
}

class BoundedCloudInvoicePageSnapshot {
  const BoundedCloudInvoicePageSnapshot({
    required this.currentPage,
    required this.totalPages,
    required this.displayedTotalRows,
    required this.rowKeys,
  });

  final int currentPage;
  final int totalPages;
  final int displayedTotalRows;
  final List<String> rowKeys;
}

enum BoundedCloudInvoicePaginationIssueCode {
  invalidPageSize,
  noPages,
  invalidPageNumber,
  inconsistentTotalPages,
  inconsistentTotalRows,
  duplicatePage,
  incompletePageSet,
  unexpectedPageRowCount,
  emptyRowKey,
  duplicateRowKey,
  extractedCountMismatch,
}

class BoundedCloudInvoicePaginationIssue {
  const BoundedCloudInvoicePaginationIssue({
    required this.code,
    required this.message,
    required this.isBlocking,
    this.pageNumber,
  });

  final BoundedCloudInvoicePaginationIssueCode code;
  final String message;
  final bool isBlocking;
  final int? pageNumber;
}

class BoundedCloudInvoicePaginationValidation {
  const BoundedCloudInvoicePaginationValidation({
    required this.selectedPageSize,
    required this.displayedTotalRows,
    required this.expectedTotalPages,
    required this.extractedRowCount,
    required this.uniqueRowCount,
    required this.issues,
  });

  final int selectedPageSize;
  final int displayedTotalRows;
  final int expectedTotalPages;
  final int extractedRowCount;
  final int uniqueRowCount;
  final List<BoundedCloudInvoicePaginationIssue> issues;

  bool get isValid => !issues.any((issue) => issue.isBlocking);
  bool get canContinueToPreview => isValid;
  bool get requiresManualCsvFallback => !isValid;
}

class BoundedCloudInvoicePaginationValidator {
  const BoundedCloudInvoicePaginationValidator();

  BoundedCloudInvoicePaginationValidation validate({
    required int selectedPageSize,
    required List<BoundedCloudInvoicePageSnapshot> pages,
  }) {
    final issues = <BoundedCloudInvoicePaginationIssue>[];
    if (selectedPageSize <= 0) {
      issues.add(
        const BoundedCloudInvoicePaginationIssue(
          code: BoundedCloudInvoicePaginationIssueCode.invalidPageSize,
          message: 'Selected page size must be greater than zero.',
          isBlocking: true,
        ),
      );
    }
    if (pages.isEmpty) {
      issues.add(
        const BoundedCloudInvoicePaginationIssue(
          code: BoundedCloudInvoicePaginationIssueCode.noPages,
          message: 'No result pages were extracted.',
          isBlocking: true,
        ),
      );
      return BoundedCloudInvoicePaginationValidation(
        selectedPageSize: selectedPageSize,
        displayedTotalRows: 0,
        expectedTotalPages: 0,
        extractedRowCount: 0,
        uniqueRowCount: 0,
        issues:
            List<BoundedCloudInvoicePaginationIssue>.unmodifiable(issues),
      );
    }

    final expectedTotalPages = pages.first.totalPages;
    final displayedTotalRows = pages.first.displayedTotalRows;
    final seenPages = <int>{};
    final seenRowKeys = <String>{};
    var extractedRowCount = 0;

    for (final page in pages) {
      if (page.currentPage <= 0 ||
          page.totalPages <= 0 ||
          page.currentPage > page.totalPages) {
        issues.add(
          BoundedCloudInvoicePaginationIssue(
            code: BoundedCloudInvoicePaginationIssueCode.invalidPageNumber,
            message: 'Page numbering is invalid.',
            isBlocking: true,
            pageNumber: page.currentPage,
          ),
        );
      }
      if (page.totalPages != expectedTotalPages) {
        issues.add(
          BoundedCloudInvoicePaginationIssue(
            code:
                BoundedCloudInvoicePaginationIssueCode.inconsistentTotalPages,
            message: 'Total page count changed during extraction.',
            isBlocking: true,
            pageNumber: page.currentPage,
          ),
        );
      }
      if (page.displayedTotalRows != displayedTotalRows) {
        issues.add(
          BoundedCloudInvoicePaginationIssue(
            code:
                BoundedCloudInvoicePaginationIssueCode.inconsistentTotalRows,
            message: 'Displayed total row count changed during extraction.',
            isBlocking: true,
            pageNumber: page.currentPage,
          ),
        );
      }
      if (!seenPages.add(page.currentPage)) {
        issues.add(
          BoundedCloudInvoicePaginationIssue(
            code: BoundedCloudInvoicePaginationIssueCode.duplicatePage,
            message: 'The same result page was extracted more than once.',
            isBlocking: true,
            pageNumber: page.currentPage,
          ),
        );
      }

      extractedRowCount += page.rowKeys.length;
      final expectedRowsOnPage = _expectedRowsOnPage(
        currentPage: page.currentPage,
        totalPages: expectedTotalPages,
        displayedTotalRows: displayedTotalRows,
        selectedPageSize: selectedPageSize,
      );
      if (expectedRowsOnPage != null &&
          page.rowKeys.length != expectedRowsOnPage) {
        issues.add(
          BoundedCloudInvoicePaginationIssue(
            code: BoundedCloudInvoicePaginationIssueCode
                .unexpectedPageRowCount,
            message:
                'Extracted row count does not match the expected count for this page.',
            isBlocking: true,
            pageNumber: page.currentPage,
          ),
        );
      }

      for (final key in page.rowKeys) {
        final normalizedKey = key.trim();
        if (normalizedKey.isEmpty) {
          issues.add(
            BoundedCloudInvoicePaginationIssue(
              code: BoundedCloudInvoicePaginationIssueCode.emptyRowKey,
              message: 'Every extracted result row requires a stable key.',
              isBlocking: true,
              pageNumber: page.currentPage,
            ),
          );
          continue;
        }
        if (!seenRowKeys.add(normalizedKey)) {
          issues.add(
            BoundedCloudInvoicePaginationIssue(
              code: BoundedCloudInvoicePaginationIssueCode.duplicateRowKey,
              message: 'A result row appeared on more than one page.',
              isBlocking: true,
              pageNumber: page.currentPage,
            ),
          );
        }
      }
    }

    if (expectedTotalPages > 0) {
      final expectedPageNumbers = <int>{
        for (var page = 1; page <= expectedTotalPages; page += 1) page,
      };
      if (seenPages.length != expectedPageNumbers.length ||
          !seenPages.containsAll(expectedPageNumbers)) {
        issues.add(
          const BoundedCloudInvoicePaginationIssue(
            code: BoundedCloudInvoicePaginationIssueCode.incompletePageSet,
            message: 'Not every result page was extracted exactly once.',
            isBlocking: true,
          ),
        );
      }
    }

    if (extractedRowCount != displayedTotalRows ||
        seenRowKeys.length != displayedTotalRows) {
      issues.add(
        const BoundedCloudInvoicePaginationIssue(
          code: BoundedCloudInvoicePaginationIssueCode.extractedCountMismatch,
          message:
              'Extracted and unique row counts must match the displayed total.',
          isBlocking: true,
        ),
      );
    }

    return BoundedCloudInvoicePaginationValidation(
      selectedPageSize: selectedPageSize,
      displayedTotalRows: displayedTotalRows,
      expectedTotalPages: expectedTotalPages,
      extractedRowCount: extractedRowCount,
      uniqueRowCount: seenRowKeys.length,
      issues: List<BoundedCloudInvoicePaginationIssue>.unmodifiable(issues),
    );
  }

  int? _expectedRowsOnPage({
    required int currentPage,
    required int totalPages,
    required int displayedTotalRows,
    required int selectedPageSize,
  }) {
    if (selectedPageSize <= 0 ||
        currentPage <= 0 ||
        totalPages <= 0 ||
        displayedTotalRows < 0) {
      return null;
    }
    if (currentPage < totalPages) return selectedPageSize;
    final remainder = displayedTotalRows % selectedPageSize;
    return remainder == 0 && displayedTotalRows > 0
        ? selectedPageSize
        : remainder;
  }
}
