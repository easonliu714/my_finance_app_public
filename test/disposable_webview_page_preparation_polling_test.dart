import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/disposable_webview_session.dart';
import 'package:my_finance_app/features/invoice/lab/official_query_page_preparation.dart';

void main() {
  test('preparation polls through reload until CSV button is enabled', () async {
    final runtime = _PreparationRuntime(<OfficialQueryPagePreparationResult>[
      _result(
        code: 'PAGE_SIZE_APPLY_TRIGGERED',
        pageSizeApplyTriggered: true,
      ),
      _result(code: 'RESULT_TABLE_RELOADING'),
      _readyResult(),
    ]);
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
      pagePreparationTimeout: const Duration(seconds: 1),
      pagePreparationInitialReloadDelay: Duration.zero,
      pagePreparationPollInterval: Duration.zero,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://example.test'));

    final result = await controller.prepareOfficialQueryPageForExport();

    expect(result.exportReady, isTrue);
    expect(result.code, 'CSV_EXPORT_READY');
    expect(runtime.preparationCalls, 3);

    await controller.cancel();
    controller.dispose();
  });

  test('preparation stops immediately for a non-retryable structural failure',
      () async {
    final runtime = _PreparationRuntime(<OfficialQueryPagePreparationResult>[
      _result(
        code: 'PAGE_SIZE_CONTROL_NOT_FOUND',
        pageSize100Requested: false,
        pageSizeAlreadyApplied: false,
      ),
      _readyResult(),
    ]);
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
      pagePreparationTimeout: const Duration(seconds: 1),
      pagePreparationInitialReloadDelay: Duration.zero,
      pagePreparationPollInterval: Duration.zero,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://example.test'));

    final result = await controller.prepareOfficialQueryPageForExport();

    expect(result.code, 'PAGE_SIZE_CONTROL_NOT_FOUND');
    expect(result.exportReady, isFalse);
    expect(runtime.preparationCalls, 1);

    await controller.cancel();
    controller.dispose();
  });
}

OfficialQueryPagePreparationResult _result({
  required String code,
  bool pageSize100Requested = true,
  bool pageSizeApplyTriggered = false,
  bool pageSizeAlreadyApplied = true,
}) {
  return OfficialQueryPagePreparationResult(
    code: code,
    routeApproved: true,
    pageSizeControlFound: true,
    pageSize100Requested: pageSize100Requested,
    pageSizeApplyControlFound: pageSizeApplyTriggered,
    pageSizeApplyTriggered: pageSizeApplyTriggered,
    pageSizeAlreadyApplied: pageSizeAlreadyApplied,
    headerCheckboxFound: false,
    headerCheckboxSelected: false,
  );
}

OfficialQueryPagePreparationResult _readyResult() {
  return const OfficialQueryPagePreparationResult(
    code: 'CSV_EXPORT_READY',
    routeApproved: true,
    pageSizeControlFound: true,
    pageSize100Requested: true,
    pageSizeApplyControlFound: true,
    pageSizeApplyTriggered: false,
    pageSizeAlreadyApplied: true,
    headerCheckboxFound: true,
    headerCheckboxSelected: true,
    resultTableStable: true,
    exportRoleMapBuilt: true,
    exportCheckboxFound: true,
    exportCheckboxRoleAmbiguous: false,
    exportCheckboxSelected: true,
    visibleExportRowCount: 100,
    checkedExportRowCount: 100,
    exportButtonFound: true,
    exportButtonEnabled: true,
  );
}

class _PreparationRuntime
    implements
        DisposableWebViewSessionRuntime,
        OfficialQueryPagePreparationRuntime {
  _PreparationRuntime(this.results);

  final List<OfficialQueryPagePreparationResult> results;
  int preparationCalls = 0;

  @override
  Future<void> open(Uri initialUri) async {}

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<OfficialQueryPagePreparationResult>
      prepareCurrentPageForExport() async {
    final index = preparationCalls < results.length
        ? preparationCalls
        : results.length - 1;
    preparationCalls += 1;
    return results[index];
  }

  @override
  Future<void> clearSession() async {}

  @override
  void dispose() {}
}
