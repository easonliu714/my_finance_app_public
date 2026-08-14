import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/authenticated_selector_capability_probe.dart';
import 'package:my_finance_app/features/invoice/lab/authenticated_selector_probe_panel.dart';
import 'package:my_finance_app/features/invoice/lab/disposable_webview_session.dart';
import 'package:my_finance_app/features/invoice/lab/official_query_page_preparation.dart';

void main() {
  testWidgets('shows only structural capability results', (tester) async {
    final runtime = _ProbeRuntime(report: _report(allCapabilities: true));
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://www.einvoice.nat.gov.tw'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthenticatedSelectorProbePanel(controller: controller),
        ),
      ),
    );

    await tester.tap(
      find.byKey(AuthenticatedSelectorProbePanel.probeButtonKey),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(AuthenticatedSelectorProbePanel.reportKey),
      findsOneWidget,
    );
    expect(find.text('符合'), findsOneWidget);
    expect(find.text('10 / 20 / 50 / 100'), findsOneWidget);
    expect(find.textContaining('發票欄位值'), findsOneWidget);
    expect(find.textContaining('<html>'), findsNothing);
    expect(find.textContaining('password'), findsNothing);

    await controller.finish();
    await tester.pump();
    expect(
      find.byKey(AuthenticatedSelectorProbePanel.reportKey),
      findsNothing,
    );
    controller.dispose();
  });

  testWidgets('explicit preparation waits for CSV export readiness', (
    tester,
  ) async {
    final runtime = _ProbeRuntime(report: _report(allCapabilities: true));
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
      pagePreparationTimeout: const Duration(seconds: 1),
      pagePreparationInitialReloadDelay: Duration.zero,
      pagePreparationPollInterval: Duration.zero,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://www.einvoice.nat.gov.tw'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthenticatedSelectorProbePanel(controller: controller),
        ),
      ),
    );

    await tester.tap(
      find.byKey(AuthenticatedSelectorProbePanel.prepareButtonKey),
    );
    await tester.pumpAndSettle();

    expect(runtime.preparationCalls, 2);
    final resultFinder = find.byKey(
      AuthenticatedSelectorProbePanel.preparationResultKey,
    );
    expect(resultFinder, findsOneWidget);
    final resultText = tester.widget<Text>(resultFinder);
    expect(resultText.data, contains('表頭全選'));

    await controller.cancel();
    controller.dispose();
  });

  testWidgets('blocked report shows manual CSV fallback', (tester) async {
    final runtime = _ProbeRuntime(report: _report(allCapabilities: false));
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://www.einvoice.nat.gov.tw'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthenticatedSelectorProbePanel(controller: controller),
        ),
      ),
    );

    await tester.tap(
      find.byKey(AuthenticatedSelectorProbePanel.probeButtonKey),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(AuthenticatedSelectorProbePanel.fallbackKey),
      findsOneWidget,
    );
    expect(find.textContaining('CSV'), findsWidgets);

    await controller.cancel();
    controller.dispose();
  });

  testWidgets('buttons remain disabled without capability runtimes', (
    tester,
  ) async {
    final controller = DisposableWebViewSessionController(
      runtimeFactory: _SessionOnlyRuntime.new,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://www.einvoice.nat.gov.tw'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthenticatedSelectorProbePanel(controller: controller),
        ),
      ),
    );

    final probeButton = tester.widget<FilledButton>(
      find.byKey(AuthenticatedSelectorProbePanel.probeButtonKey),
    );
    final prepareButton = tester.widget<OutlinedButton>(
      find.byKey(AuthenticatedSelectorProbePanel.prepareButtonKey),
    );
    expect(probeButton.onPressed, isNull);
    expect(prepareButton.onPressed, isNull);

    await controller.cancel();
    controller.dispose();
  });
}

AuthenticatedSelectorCapabilityReport _report({
  required bool allCapabilities,
}) {
  final matches = <AuthenticatedSelectorCapability,
      AuthenticatedSelectorCapabilityMatch>{
    for (final capability in AuthenticatedSelectorCapability.values)
      capability: AuthenticatedSelectorCapabilityMatch(
        capability: capability,
        matchCount: allCapabilities ? 1 : 0,
        maximumMatches: 1,
      ),
  };
  return AuthenticatedSelectorCapabilityReport(
    probeSucceeded: true,
    routeApproved: true,
    matches: matches,
    availablePageSizes: allCapabilities
        ? const <int>[10, 20, 50, 100]
        : const <int>[],
    headerMatches: <String, bool>{
      for (final header in expectedOfficialResultHeaders)
        header: allCapabilities,
    },
    issues: allCapabilities
        ? const <AuthenticatedSelectorProbeIssue>[]
        : const <AuthenticatedSelectorProbeIssue>[
            AuthenticatedSelectorProbeIssue(
              code: AuthenticatedSelectorProbeIssueCode.missingCapability,
              message: 'Required query controls are unavailable.',
              isBlocking: true,
            ),
          ],
  );
}

class _ProbeRuntime
    implements
        DisposableWebViewSessionRuntime,
        AuthenticatedSelectorCapabilityProbeRuntime,
        OfficialQueryPagePreparationRuntime {
  _ProbeRuntime({required this.report});

  final AuthenticatedSelectorCapabilityReport report;
  int preparationCalls = 0;

  @override
  Future<void> open(Uri initialUri) async {}

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<AuthenticatedSelectorCapabilityReport>
      probeSelectorCapabilities() async => report;

  @override
  Future<OfficialQueryPagePreparationResult>
      prepareCurrentPageForExport() async {
    preparationCalls += 1;
    if (preparationCalls == 1) {
      return const OfficialQueryPagePreparationResult(
        code: 'PAGE_SIZE_APPLY_TRIGGERED',
        routeApproved: true,
        pageSizeControlFound: true,
        pageSize100Requested: true,
        pageSizeApplyControlFound: true,
        pageSizeApplyTriggered: true,
        pageSizeAlreadyApplied: false,
        headerCheckboxFound: false,
        headerCheckboxSelected: false,
      );
    }
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

  @override
  Future<void> clearSession() async {}

  @override
  void dispose() {}
}

class _SessionOnlyRuntime implements DisposableWebViewSessionRuntime {
  @override
  Future<void> open(Uri initialUri) async {}

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<void> clearSession() async {}

  @override
  void dispose() {}
}
