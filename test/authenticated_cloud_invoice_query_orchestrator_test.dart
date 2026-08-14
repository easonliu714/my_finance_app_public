import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/authenticated_cloud_invoice_query_orchestrator.dart';

void main() {
  group('AuthenticatedCloudInvoiceQueryPlanner', () {
    const planner = AuthenticatedCloudInvoiceQueryPlanner();

    test('requires an initial date when no checkpoint exists', () {
      final plan = planner.createPlan(
        today: DateTime(2026, 6, 17),
        checkpoint: const CloudInvoiceQueryCheckpoint(),
      );

      expect(plan.isBlocked, isTrue);
      expect(plan.requiresInitialStartDate, isTrue);
      expect(plan.windows, isEmpty);
    });

    test('uses a 48-hour overlap and splits windows by calendar month', () {
      final plan = planner.createPlan(
        today: DateTime(2026, 6, 17, 23, 59),
        checkpoint: CloudInvoiceQueryCheckpoint(
          lastSuccessfulQueryEndDate: DateTime(2026, 5, 31),
          latestImportedInvoiceDate: DateTime(2026, 5, 30),
          lastImportedInvoiceKey: 'AG90000006|2026-05-30|24813702',
        ),
      );

      expect(plan.canRun, isTrue);
      expect(plan.usedCheckpoint, isTrue);
      expect(plan.overlapDays, 2);
      expect(plan.windows, hasLength(2));
      expect(plan.windows[0].startDate, DateTime(2026, 5, 29));
      expect(plan.windows[0].endDate, DateTime(2026, 5, 31));
      expect(plan.windows[1].startDate, DateTime(2026, 6, 1));
      expect(plan.windows[1].endDate, DateTime(2026, 6, 17));
      expect(
        plan.windows.every((window) => window.isSingleCalendarMonth),
        isTrue,
      );
    });

    test('uses latest imported invoice date when query end is unavailable', () {
      final plan = planner.createPlan(
        today: DateTime(2026, 6, 3),
        checkpoint: CloudInvoiceQueryCheckpoint(
          latestImportedInvoiceDate: DateTime(2026, 5, 31),
        ),
      );

      expect(plan.canRun, isTrue);
      expect(plan.windows.first.startDate, DateTime(2026, 5, 29));
      expect(plan.windows.last.endDate, DateTime(2026, 6, 3));
    });

    test('first import uses the explicit start date and splits every month', () {
      final plan = planner.createPlan(
        today: DateTime(2026, 6, 17),
        checkpoint: const CloudInvoiceQueryCheckpoint(),
        initialStartDate: DateTime(2026, 4, 20),
      );

      expect(plan.canRun, isTrue);
      expect(plan.usedCheckpoint, isFalse);
      expect(plan.windows, hasLength(3));
      expect(plan.windows[0].startDate, DateTime(2026, 4, 20));
      expect(plan.windows[0].endDate, DateTime(2026, 4, 30));
      expect(plan.windows[1].startDate, DateTime(2026, 5, 1));
      expect(plan.windows[1].endDate, DateTime(2026, 5, 31));
      expect(plan.windows[2].startDate, DateTime(2026, 6, 1));
      expect(plan.windows[2].endDate, DateTime(2026, 6, 17));
    });

    test('allowed earliest date clamps the overlap window', () {
      final plan = planner.createPlan(
        today: DateTime(2026, 6, 17),
        checkpoint: CloudInvoiceQueryCheckpoint(
          lastSuccessfulQueryEndDate: DateTime(2026, 5, 2),
        ),
        allowedEarliestDate: DateTime(2026, 5, 1),
      );

      expect(plan.canRun, isTrue);
      expect(plan.windows, hasLength(2));
      expect(plan.windows[0].startDate, DateTime(2026, 5, 1));
      expect(plan.windows[0].endDate, DateTime(2026, 5, 31));
      expect(plan.windows[1].startDate, DateTime(2026, 6, 1));
      expect(plan.windows[1].endDate, DateTime(2026, 6, 17));
    });

    test('future checkpoint blocks the plan', () {
      final plan = planner.createPlan(
        today: DateTime(2026, 6, 17),
        checkpoint: CloudInvoiceQueryCheckpoint(
          lastSuccessfulQueryEndDate: DateTime(2026, 6, 18),
        ),
      );

      expect(plan.isBlocked, isTrue);
      expect(plan.windows, isEmpty);
      expect(
        plan.issues.single.code,
        CloudInvoiceQueryPlanIssueCode.resumeDateInFuture,
      );
    });

    test('future first-import start date blocks the plan', () {
      final plan = planner.createPlan(
        today: DateTime(2026, 6, 17),
        checkpoint: const CloudInvoiceQueryCheckpoint(),
        initialStartDate: DateTime(2026, 6, 18),
      );

      expect(plan.isBlocked, isTrue);
      expect(
        plan.issues.single.code,
        CloudInvoiceQueryPlanIssueCode.invalidDateRange,
      );
    });
  });

  group('CloudInvoicePageSizePlanner', () {
    const planner = CloudInvoicePageSizePlanner();

    test('prefers 100 rows when the page exposes it', () {
      final plan = planner.createPlan(<int>[10, 20, 50, 100]);

      expect(plan.canApply, isTrue);
      expect(plan.selectedPageSize, 100);
      expect(plan.selectedPreferredHundred, isTrue);
    });

    test('uses the largest supported value when 100 is unavailable', () {
      final plan = planner.createPlan(<int>[20, 50, 30, 50, -1, 0]);

      expect(plan.canApply, isTrue);
      expect(plan.availablePageSizes, <int>[20, 30, 50]);
      expect(plan.selectedPageSize, 50);
      expect(plan.selectedPreferredHundred, isFalse);
    });

    test('blocks when the page exposes no usable size', () {
      final plan = planner.createPlan(<int>[0, -10]);

      expect(plan.canApply, isFalse);
      expect(plan.selectedPageSize, isNull);
      expect(plan.issues.single.isBlocking, isTrue);
    });
  });

  group('BoundedCloudInvoicePaginationValidator', () {
    const validator = BoundedCloudInvoicePaginationValidator();

    test('accepts every page exactly once with reconciled row counts', () {
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: <BoundedCloudInvoicePageSnapshot>[
          _page(1, 3, 250, 0, 100),
          _page(2, 3, 250, 100, 100),
          _page(3, 3, 250, 200, 50),
        ],
      );

      expect(validation.isValid, isTrue);
      expect(validation.canContinueToPreview, isTrue);
      expect(validation.requiresManualCsvFallback, isFalse);
      expect(validation.extractedRowCount, 250);
      expect(validation.uniqueRowCount, 250);
    });

    test('supports a valid empty-result page', () {
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: const <BoundedCloudInvoicePageSnapshot>[
          BoundedCloudInvoicePageSnapshot(
            currentPage: 1,
            totalPages: 1,
            displayedTotalRows: 0,
            rowKeys: <String>[],
          ),
        ],
      );

      expect(validation.isValid, isTrue);
      expect(validation.extractedRowCount, 0);
    });

    test('missing page requires manual CSV fallback', () {
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: <BoundedCloudInvoicePageSnapshot>[
          _page(1, 3, 250, 0, 100),
          _page(3, 3, 250, 200, 50),
        ],
      );

      expect(validation.isValid, isFalse);
      expect(validation.requiresManualCsvFallback, isTrue);
      expect(
        validation.issues.map((issue) => issue.code),
        contains(BoundedCloudInvoicePaginationIssueCode.incompletePageSet),
      );
    });

    test('changing total row count fails closed', () {
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: <BoundedCloudInvoicePageSnapshot>[
          _page(1, 2, 150, 0, 100),
          _page(2, 2, 151, 100, 50),
        ],
      );

      expect(validation.isValid, isFalse);
      expect(
        validation.issues.map((issue) => issue.code),
        contains(
          BoundedCloudInvoicePaginationIssueCode.inconsistentTotalRows,
        ),
      );
    });

    test('duplicate row key across pages fails closed', () {
      final firstPage = _page(1, 2, 101, 0, 100);
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: <BoundedCloudInvoicePageSnapshot>[
          firstPage,
          const BoundedCloudInvoicePageSnapshot(
            currentPage: 2,
            totalPages: 2,
            displayedTotalRows: 101,
            rowKeys: <String>['row-0'],
          ),
        ],
      );

      expect(validation.isValid, isFalse);
      expect(
        validation.issues.map((issue) => issue.code),
        contains(BoundedCloudInvoicePaginationIssueCode.duplicateRowKey),
      );
      expect(validation.requiresManualCsvFallback, isTrue);
    });

    test('unexpected number of rows on a page fails closed', () {
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: <BoundedCloudInvoicePageSnapshot>[
          _page(1, 2, 150, 0, 99),
          _page(2, 2, 150, 99, 51),
        ],
      );

      expect(validation.isValid, isFalse);
      expect(
        validation.issues.map((issue) => issue.code),
        contains(
          BoundedCloudInvoicePaginationIssueCode.unexpectedPageRowCount,
        ),
      );
    });

    test('empty stable row key fails closed', () {
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: const <BoundedCloudInvoicePageSnapshot>[
          BoundedCloudInvoicePageSnapshot(
            currentPage: 1,
            totalPages: 1,
            displayedTotalRows: 1,
            rowKeys: <String>['  '],
          ),
        ],
      );

      expect(validation.isValid, isFalse);
      expect(
        validation.issues.map((issue) => issue.code),
        contains(BoundedCloudInvoicePaginationIssueCode.emptyRowKey),
      );
    });

    test('no page snapshot requires CSV fallback', () {
      final validation = validator.validate(
        selectedPageSize: 100,
        pages: const <BoundedCloudInvoicePageSnapshot>[],
      );

      expect(validation.isValid, isFalse);
      expect(validation.requiresManualCsvFallback, isTrue);
      expect(
        validation.issues.single.code,
        BoundedCloudInvoicePaginationIssueCode.noPages,
      );
    });
  });
}

BoundedCloudInvoicePageSnapshot _page(
  int currentPage,
  int totalPages,
  int displayedTotalRows,
  int firstRowIndex,
  int rowCount,
) {
  return BoundedCloudInvoicePageSnapshot(
    currentPage: currentPage,
    totalPages: totalPages,
    displayedTotalRows: displayedTotalRows,
    rowKeys: List<String>.generate(
      rowCount,
      (index) => 'row-${firstRowIndex + index}',
    ),
  );
}
