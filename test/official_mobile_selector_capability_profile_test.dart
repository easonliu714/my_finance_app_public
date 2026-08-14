import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/authenticated_selector_capability_probe.dart';
import 'package:my_finance_app/features/invoice/lab/official_mobile_selector_capability_profile.dart';
import 'package:my_finance_app/features/invoice/lab/official_mobile_selector_result_context.dart';
import 'package:my_finance_app/features/invoice/lab/official_mobile_webview_fit_width.dart';

void main() {
  const parser =
      ContextAwareOfficialMobileSelectorCapabilityReportParser();

  test('query page permits required controls while optional controls are absent', () {
    final counts = <String, int>{
      for (final capability in AuthenticatedSelectorCapability.values)
        capability.id: 0,
    };
    for (final capability in officialMobileRequiredQueryControls) {
      counts[capability.id] = 1;
    }

    final report = parser.parse(
      jsonEncode(
        _payload(
          capabilityCounts: counts,
          matchedHeaders: const <String>[],
        ),
      ),
    );

    expect(report.routeApproved, isTrue);
    expect(report.isBlocked, isFalse);
    expect(report.canProceedToQueryPopulation, isTrue);
    expect(report.canProceedToResultExtraction, isFalse);
    expect(report.requiresManualCsvFallback, isFalse);
  });

  test('result page remains usable when query controls are no longer visible', () {
    final counts = <String, int>{
      for (final capability in AuthenticatedSelectorCapability.values)
        capability.id: 0,
      AuthenticatedSelectorCapability.resultTable.id: 1,
    };

    final report = parser.parse(
      jsonEncode(
        _payload(
          capabilityCounts: counts,
          matchedHeaders: officialMobileRequiredResultHeaders.toList(),
        ),
      ),
    );

    expect(report.routeApproved, isTrue);
    expect(report.isBlocked, isFalse);
    expect(report.canProceedToQueryPopulation, isFalse);
    expect(report.canProceedToResultExtraction, isTrue);
    expect(report.requiresManualCsvFallback, isFalse);
  });

  test('non-approved route still fails closed', () {
    final payload = _payload(
      capabilityCounts: <String, int>{
        for (final capability in AuthenticatedSelectorCapability.values)
          capability.id: 1,
      },
      matchedHeaders: expectedOfficialResultHeaders,
    )..['routeApproved'] = false;

    final report = parser.parse(jsonEncode(payload));

    expect(report.isBlocked, isTrue);
    expect(report.canProceedToQueryPopulation, isFalse);
    expect(report.canProceedToResultExtraction, isFalse);
    expect(report.requiresManualCsvFallback, isTrue);
  });

  test('selector and fit-width scripts return structural information only', () {
    final selectorScript = buildOfficialMobileSelectorCapabilityProbeScript();
    final fitWidthScript = buildOfficialMobileFitWidthScript();

    expect(selectorScript, contains('查詢發票日期起迄'));
    expect(selectorScript, contains('歸戶載具列表'));
    expect(selectorScript, contains('發票號碼'));
    expect(selectorScript, contains('availablePageSizes'));
    expect(selectorScript, isNot(contains('innerHTML')));
    expect(selectorScript, isNot(contains('outerHTML')));
    expect(selectorScript, isNot(contains('document.cookie')));
    expect(selectorScript, isNot(contains('localStorage')));
    expect(selectorScript, isNot(contains('sessionStorage')));
    expect(selectorScript, isNot(contains('fetch(')));
    expect(selectorScript, isNot(contains('XMLHttpRequest')));

    expect(fitWidthScript, contains('scrollWidth'));
    expect(fitWidthScript, contains('clientWidth'));
    expect(fitWidthScript, contains('body.style.zoom'));
    expect(fitWidthScript, isNot(contains('document.cookie')));
    expect(fitWidthScript, isNot(contains('localStorage')));
    expect(fitWidthScript, isNot(contains('textContent')));
    expect(fitWidthScript, isNot(contains('.value')));
  });
}

Map<String, Object?> _payload({
  required Map<String, int> capabilityCounts,
  required List<String> matchedHeaders,
}) {
  return <String, Object?>{
    'schemaVersion': authenticatedSelectorProbeSchemaVersion,
    'probeSucceeded': true,
    'routeApproved': true,
    'capabilities': capabilityCounts,
    'availablePageSizes': const <int>[],
    'headers': <String, bool>{
      for (final header in expectedOfficialResultHeaders)
        header: matchedHeaders.contains(header),
    },
    'errorCode': null,
  };
}
