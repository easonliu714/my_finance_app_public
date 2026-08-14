import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/authenticated_selector_capability_probe.dart';

void main() {
  const parser = AuthenticatedSelectorCapabilityReportParser();

  test('allows query population when all query controls match exactly once', () {
    final report = parser.parse(
      jsonEncode(
        _payload(
          capabilityCounts: <String, int>{
            for (final capability in AuthenticatedSelectorCapability.values)
              capability.id:
                  capability.requiredForQueryPopulation ? 1 : 0,
          },
          pageSizes: const <int>[],
          matchedHeaders: const <String>[],
        ),
      ),
    );

    expect(report.probeSucceeded, isTrue);
    expect(report.routeApproved, isTrue);
    expect(report.isBlocked, isFalse);
    expect(report.canProceedToQueryPopulation, isTrue);
    expect(report.canProceedToResultExtraction, isFalse);
    expect(report.requiresManualCsvFallback, isFalse);
  });

  test('allows result extraction only when result controls and headers match', () {
    final report = parser.parse(
      jsonEncode(
        _payload(
          capabilityCounts: <String, int>{
            for (final capability in AuthenticatedSelectorCapability.values)
              capability.id: 1,
          },
          pageSizes: const <int>[10, 20, 50, 100],
          matchedHeaders: expectedOfficialResultHeaders,
        ),
      ),
    );

    expect(report.isBlocked, isFalse);
    expect(report.canProceedToQueryPopulation, isTrue);
    expect(report.canProceedToResultExtraction, isTrue);
    expect(report.availablePageSizes, <int>[10, 20, 50, 100]);
  });

  test('rejects a non-approved route', () {
    final payload = _payload(
      capabilityCounts: <String, int>{
        for (final capability in AuthenticatedSelectorCapability.values)
          capability.id: 1,
      },
      pageSizes: const <int>[100],
      matchedHeaders: expectedOfficialResultHeaders,
    )..['routeApproved'] = false;
    final report = parser.parse(jsonEncode(payload));

    expect(report.isBlocked, isTrue);
    expect(report.canProceedToQueryPopulation, isFalse);
    expect(report.requiresManualCsvFallback, isTrue);
    expect(
      report.issues.map((issue) => issue.code),
      contains(AuthenticatedSelectorProbeIssueCode.routeNotApproved),
    );
  });

  test('fails closed when a query control matches more than once', () {
    final counts = <String, int>{
      for (final capability in AuthenticatedSelectorCapability.values)
        capability.id: 1,
    };
    counts[AuthenticatedSelectorCapability.queryButton.id] = 2;
    final report = parser.parse(
      jsonEncode(
        _payload(
          capabilityCounts: counts,
          pageSizes: const <int>[100],
          matchedHeaders: expectedOfficialResultHeaders,
        ),
      ),
    );

    expect(report.isBlocked, isTrue);
    expect(report.canProceedToQueryPopulation, isFalse);
    expect(
      report.issues.map((issue) => issue.code),
      contains(AuthenticatedSelectorProbeIssueCode.ambiguousCapability),
    );
  });

  test('missing result structure is non-blocking before a query runs', () {
    final report = parser.parse(
      jsonEncode(
        _payload(
          capabilityCounts: <String, int>{
            for (final capability in AuthenticatedSelectorCapability.values)
              capability.id:
                  capability.requiredForQueryPopulation ? 1 : 0,
          },
          pageSizes: const <int>[],
          matchedHeaders: const <String>[],
        ),
      ),
    );

    expect(report.isBlocked, isFalse);
    expect(report.canProceedToQueryPopulation, isTrue);
    expect(report.canProceedToResultExtraction, isFalse);
  });

  test('rejects unknown capability fields', () {
    final payload = _payload(
      capabilityCounts: <String, int>{
        for (final capability in AuthenticatedSelectorCapability.values)
          capability.id: 1,
        'rawPageText': 1,
      },
      pageSizes: const <int>[100],
      matchedHeaders: expectedOfficialResultHeaders,
    );
    final report = parser.parse(jsonEncode(payload));

    expect(report.isBlocked, isTrue);
    expect(
      report.issues.map((issue) => issue.code),
      contains(AuthenticatedSelectorProbeIssueCode.unexpectedCapability),
    );
  });

  test('rejects unsupported top-level fields', () {
    final payload = _payload(
      capabilityCounts: <String, int>{
        for (final capability in AuthenticatedSelectorCapability.values)
          capability.id: 1,
      },
      pageSizes: const <int>[100],
      matchedHeaders: expectedOfficialResultHeaders,
    )..['html'] = '<html></html>';
    final report = parser.parse(jsonEncode(payload));

    expect(report.isBlocked, isTrue);
    expect(
      report.issues.single.code,
      AuthenticatedSelectorProbeIssueCode.invalidPayload,
    );
  });

  test('rejects invalid page-size values', () {
    final payload = _payload(
      capabilityCounts: <String, int>{
        for (final capability in AuthenticatedSelectorCapability.values)
          capability.id: 1,
      },
      pageSizes: const <Object>[100, 'all'],
      matchedHeaders: expectedOfficialResultHeaders,
    );
    final report = parser.parse(jsonEncode(payload));

    expect(report.isBlocked, isTrue);
    expect(
      report.issues.map((issue) => issue.code),
      contains(AuthenticatedSelectorProbeIssueCode.invalidPageSize),
    );
  });

  test('decodes a double-encoded JavaScript result', () {
    final payload = jsonEncode(
      _payload(
        capabilityCounts: <String, int>{
          for (final capability in AuthenticatedSelectorCapability.values)
            capability.id: 1,
        },
        pageSizes: const <int>[100],
        matchedHeaders: expectedOfficialResultHeaders,
      ),
    );
    final report = parser.parse(jsonEncode(payload));

    expect(report.canProceedToResultExtraction, isTrue);
  });

  test('generated script is route-bound and returns structural data only', () {
    final script = buildAuthenticatedSelectorCapabilityProbeScript();

    expect(script, contains(approvedCloudInvoiceQueryOrigin));
    expect(script, contains(approvedCloudInvoiceQueryPath));
    expect(script, contains('document.querySelectorAll'));
    expect(script, contains('availablePageSizes'));
    expect(script, contains('headers'));
    expect(script, isNot(contains('innerHTML')));
    expect(script, isNot(contains('outerHTML')));
    expect(script, isNot(contains('document.cookie')));
    expect(script, isNot(contains('localStorage')));
    expect(script, isNot(contains('sessionStorage')));
    expect(script, isNot(contains('fetch(')));
    expect(script, isNot(contains('XMLHttpRequest')));
  });
}

Map<String, Object?> _payload({
  required Map<String, int> capabilityCounts,
  required List<Object> pageSizes,
  required List<String> matchedHeaders,
}) {
  return <String, Object?>{
    'schemaVersion': authenticatedSelectorProbeSchemaVersion,
    'probeSucceeded': true,
    'routeApproved': true,
    'capabilities': capabilityCounts,
    'availablePageSizes': pageSizes,
    'headers': <String, bool>{
      for (final header in expectedOfficialResultHeaders)
        header: matchedHeaders.contains(header),
    },
    'errorCode': null,
  };
}
