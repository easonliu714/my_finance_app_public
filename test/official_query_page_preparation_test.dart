import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_query_page_preparation.dart';

void main() {
  test('preparation script applies 100 rows before export role mapping', () {
    final script = buildOfficialQueryPagePreparationScript();

    expect(script, contains('const prepareExportSelection = true'));
    expect(script, contains('PAGE_SIZE_APPLY_TRIGGERED'));
    expect(script, contains('__mfaPageSizeApplyIssuedAt'));
    expect(script, contains('RESULT_TABLE_RELOADING'));
    expect(script, contains('getBoundingClientRect'));
    expect(script, contains('consistentClusters'));
    expect(script, contains('CSV_EXPORT_CHECKBOX_ROLE_AMBIGUOUS'));
    expect(script, contains('CSV_EXPORT_SELECTION_INCOMPLETE'));
    expect(script, contains('CSV_EXPORT_BUTTON_STILL_DISABLED'));
    expect(script, contains('CSV_EXPORT_READY'));
    expect(script, contains('aria-disabled'));
    expect(script, contains('pointerEvents'));
    expect(script, isNot(contains('XMLHttpRequest')));
    expect(script, isNot(contains('innerHTML')));
    expect(script, isNot(contains('outerHTML')));
  });

  test('detail preparation requests 100 rows and returns before export mutation',
      () {
    final script = buildOfficialQueryPagePreparationScript(
      prepareExportSelection: false,
    );

    expect(script, contains('const prepareExportSelection = false'));
    expect(script, contains("return finish('DETAIL_PAGE_SIZE_READY')"));
    final detailReady = script.indexOf("return finish('DETAIL_PAGE_SIZE_READY')");
    final exportSelection = script.indexOf('const rowEntries = []');
    expect(detailReady, greaterThan(0));
    expect(exportSelection, greaterThan(detailReady));
    expect(script, isNot(contains('XMLHttpRequest')));
    expect(script, isNot(contains('innerHTML')));
    expect(script, isNot(contains('outerHTML')));
  });

  test('finalizer reuses the same reload-safe export role map', () {
    final preparation = buildOfficialQueryPagePreparationScript();
    final finalizer = buildOfficialQueryPageFinalizePreparationScript();

    expect(finalizer, preparation);
    expect(finalizer, contains('stableWindowMs = 700'));
    expect(finalizer, contains('checkedExportRowCount'));
  });

  test('parses strict CSV export ready report', () {
    final result = OfficialQueryPagePreparationResult.fromRaw(
      '{"code":"CSV_EXPORT_READY","routeApproved":true,'
      '"pageSizeControlFound":true,"pageSize100Requested":true,'
      '"pageSizeApplyControlFound":true,"pageSizeApplyTriggered":false,'
      '"pageSizeAlreadyApplied":true,'
      '"headerCheckboxFound":true,"headerCheckboxSelected":true,'
      '"resultTableStable":true,"exportRoleMapBuilt":true,'
      '"exportCheckboxFound":true,"exportCheckboxRoleAmbiguous":false,'
      '"exportCheckboxSelected":true,"visibleExportRowCount":100,'
      '"checkedExportRowCount":100,"exportButtonFound":true,'
      '"exportButtonEnabled":true}',
    );

    expect(result.accepted, isTrue);
    expect(result.exportReady, isTrue);
    expect(result.detailReady, isFalse);
    expect(result.visibleExportRowCount, 100);
  });

  test('parses strict 100-row detail readiness without export selection', () {
    final result = OfficialQueryPagePreparationResult.fromRaw(
      '{"code":"DETAIL_PAGE_SIZE_READY","routeApproved":true,'
      '"pageSizeControlFound":true,"pageSize100Requested":true,'
      '"pageSizeApplyControlFound":true,"pageSizeApplyTriggered":false,'
      '"pageSizeAlreadyApplied":true,"resultTableStable":true,'
      '"headerCheckboxFound":false,"headerCheckboxSelected":false}',
    );

    expect(result.accepted, isTrue);
    expect(result.detailReady, isTrue);
    expect(result.exportReady, isFalse);
    expect(result.exportCheckboxSelected, isFalse);
  });

  test('apply-triggered result is accepted but not ready yet', () {
    final result = OfficialQueryPagePreparationResult.fromRaw(
      '{"code":"PAGE_SIZE_APPLY_TRIGGERED","routeApproved":true,'
      '"pageSizeControlFound":true,"pageSize100Requested":true,'
      '"pageSizeApplyControlFound":true,"pageSizeApplyTriggered":true,'
      '"pageSizeAlreadyApplied":false,'
      '"headerCheckboxFound":false,"headerCheckboxSelected":false}',
    );

    expect(result.accepted, isTrue);
    expect(result.exportReady, isFalse);
    expect(result.detailReady, isFalse);
  });

  test('disabled CSV button fails strict readiness gate', () {
    final result = OfficialQueryPagePreparationResult.fromRaw(
      '{"code":"CSV_EXPORT_BUTTON_STILL_DISABLED",'
      '"routeApproved":true,"pageSizeControlFound":true,'
      '"pageSize100Requested":true,"pageSizeAlreadyApplied":true,'
      '"resultTableStable":true,"exportRoleMapBuilt":true,'
      '"exportCheckboxFound":true,"exportCheckboxSelected":true,'
      '"visibleExportRowCount":100,"checkedExportRowCount":100,'
      '"exportButtonFound":true,"exportButtonEnabled":false}',
    );

    expect(result.accepted, isFalse);
    expect(result.exportReady, isFalse);
  });

  test('changing the select without applying fails closed', () {
    final result = OfficialQueryPagePreparationResult.fromRaw(
      '{"code":"PAGE_SIZE_APPLY_CONTROL_NOT_FOUND",'
      '"routeApproved":true,"pageSizeControlFound":true,'
      '"pageSize100Requested":true}',
    );

    expect(result.accepted, isFalse);
    expect(result.exportReady, isFalse);
    expect(result.detailReady, isFalse);
  });

  test('invalid preparation response fails closed', () {
    final result = OfficialQueryPagePreparationResult.fromRaw('not-json');

    expect(result.accepted, isFalse);
    expect(result.exportReady, isFalse);
    expect(result.detailReady, isFalse);
    expect(result.code, 'PAGE_PREPARATION_RESPONSE_INVALID');
  });
}
