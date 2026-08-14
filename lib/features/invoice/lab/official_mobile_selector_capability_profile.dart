import 'dart:convert';

import 'authenticated_selector_capability_probe.dart';

const Set<AuthenticatedSelectorCapability> officialMobileRequiredQueryControls =
    <AuthenticatedSelectorCapability>{
  AuthenticatedSelectorCapability.startDate,
  AuthenticatedSelectorCapability.endDate,
  AuthenticatedSelectorCapability.carrierSelector,
  AuthenticatedSelectorCapability.queryButton,
};

const Set<AuthenticatedSelectorCapability> officialMobileRequiredResultControls =
    <AuthenticatedSelectorCapability>{
  AuthenticatedSelectorCapability.resultTable,
};

const Set<String> officialMobileRequiredResultHeaders = <String>{
  '發票號碼',
  '發票金額',
  '發票日期',
};

bool isOfficialMobileRequiredCapability(
  AuthenticatedSelectorCapability capability,
) {
  return officialMobileRequiredQueryControls.contains(capability) ||
      officialMobileRequiredResultControls.contains(capability);
}

class OfficialMobileSelectorCapabilityReport
    extends AuthenticatedSelectorCapabilityReport {
  const OfficialMobileSelectorCapabilityReport({
    required super.probeSucceeded,
    required super.routeApproved,
    required super.matches,
    required super.availablePageSizes,
    required super.headerMatches,
    required super.issues,
  });

  @override
  bool get canProceedToQueryPopulation =>
      probeSucceeded &&
      routeApproved &&
      !isBlocked &&
      officialMobileRequiredQueryControls.every(
        (capability) => matches[capability]?.valid ?? false,
      );

  @override
  bool get canProceedToResultExtraction =>
      canProceedToQueryPopulation &&
      officialMobileRequiredResultControls.every(
        (capability) => matches[capability]?.valid ?? false,
      ) &&
      officialMobileRequiredResultHeaders.every(
        (header) => headerMatches[header] ?? false,
      );

  @override
  bool get requiresManualCsvFallback => !canProceedToQueryPopulation;
}

class OfficialMobileSelectorCapabilityReportParser
    extends AuthenticatedSelectorCapabilityReportParser {
  const OfficialMobileSelectorCapabilityReportParser();

  @override
  AuthenticatedSelectorCapabilityReport parse(Object? rawResult) {
    final base = super.parse(rawResult);
    final adjustedIssues = base.issues.map((issue) {
      final capability = issue.capability;
      if (capability == null ||
          isOfficialMobileRequiredCapability(capability) ||
          issue.code == AuthenticatedSelectorProbeIssueCode.routeNotApproved ||
          issue.code ==
              AuthenticatedSelectorProbeIssueCode.probeExecutionFailed ||
          issue.code == AuthenticatedSelectorProbeIssueCode.invalidPayload ||
          issue.code ==
              AuthenticatedSelectorProbeIssueCode.unsupportedSchemaVersion ||
          issue.code ==
              AuthenticatedSelectorProbeIssueCode.unexpectedCapability ||
          issue.code == AuthenticatedSelectorProbeIssueCode.unexpectedHeader ||
          issue.code == AuthenticatedSelectorProbeIssueCode.invalidPageSize) {
        return issue;
      }
      return AuthenticatedSelectorProbeIssue(
        code: issue.code,
        message: issue.message,
        isBlocking: false,
        capability: capability,
        header: issue.header,
      );
    }).toList(growable: false);

    return OfficialMobileSelectorCapabilityReport(
      probeSucceeded: base.probeSucceeded,
      routeApproved: base.routeApproved,
      matches: base.matches,
      availablePageSizes: base.availablePageSizes,
      headerMatches: base.headerMatches,
      issues: adjustedIssues,
    );
  }
}

String buildOfficialMobileSelectorCapabilityProbeScript() {
  final encodedOrigin = jsonEncode(approvedCloudInvoiceQueryOrigin);
  final encodedPath = jsonEncode(approvedCloudInvoiceQueryPath);
  final encodedHeaders = jsonEncode(expectedOfficialResultHeaders);

  return '''
(() => {
  const schemaVersion = $authenticatedSelectorProbeSchemaVersion;
  const approvedOrigin = $encodedOrigin;
  const approvedPath = $encodedPath;
  const expectedHeaders = $encodedHeaders;
  const normalize = (value) => String(value || '')
    .replace(/\\s+/g, '')
    .replace(/[＊*：:]/g, '')
    .trim();
  const uniqueCount = (elements) => new Set(elements.filter(Boolean)).size;
  const cssElements = (selectors) => {
    const output = [];
    for (const selector of selectors) {
      for (const element of document.querySelectorAll(selector)) {
        output.push(element);
      }
    }
    return output;
  };
  const controlNearLabel = (labels, controlSelector) => {
    const normalizedLabels = labels.map(normalize);
    const output = [];
    const labelNodes = document.querySelectorAll(
      'label,[aria-label],.form-label,.field-label,.mat-form-field-label,' +
      '[class*="label"],h1,h2,h3,h4,p,span,div'
    );
    for (const node of labelNodes) {
      const text = normalize(
        node.getAttribute?.('aria-label') || node.textContent || ''
      );
      if (!normalizedLabels.some((label) => text.includes(label))) continue;
      if (node.htmlFor) output.push(document.getElementById(node.htmlFor));
      for (const element of node.querySelectorAll?.(controlSelector) || []) {
        output.push(element);
      }
      const parent = node.parentElement;
      if (parent) {
        for (const element of parent.querySelectorAll(controlSelector)) {
          output.push(element);
        }
      }
      const next = node.nextElementSibling;
      if (next?.matches?.(controlSelector)) output.push(next);
      for (const element of next?.querySelectorAll?.(controlSelector) || []) {
        output.push(element);
      }
    }
    return uniqueCount(output);
  };
  const buttonTextCount = (labels) => {
    const accepted = labels.map(normalize);
    return uniqueCount(
      Array.from(document.querySelectorAll(
        'button,input[type="button"],input[type="submit"],input[type="reset"],' +
        '[role="button"]'
      )).filter((element) => {
        const text = normalize(
          element.textContent || element.value || element.getAttribute('aria-label')
        );
        return accepted.includes(text);
      })
    );
  };
  const headerNodes = Array.from(document.querySelectorAll(
    'th,[role="columnheader"],thead td,.table-header,[class*="header"]'
  ));
  const normalizedHeaders = headerNodes.map((node) => normalize(node.textContent));
  const headerFound = (header) => normalizedHeaders.some(
    (value) => value === normalize(header) || value.includes(normalize(header))
  );

  try {
    const routeApproved =
      window.location.origin === approvedOrigin &&
      window.location.pathname === approvedPath;

    const dateControls = uniqueCount([
      ...cssElements([
        'input[type="date"]',
        'input[placeholder*="日期"]',
        '[role="textbox"][aria-label*="日期"]',
        '.mat-date-range-input input',
        '[class*="date-range"] input',
      ]),
      ...cssElements(['input']).filter((element) => {
        const label = normalize(
          element.getAttribute('aria-label') ||
          element.getAttribute('placeholder') || ''
        );
        return label.includes('日期');
      }),
    ]);
    const labelledDateControls = controlNearLabel(
      ['查詢發票日期起迄', '發票日期起迄'],
      'input,[role="textbox"],button'
    );
    const effectiveDateCount = Math.max(dateControls, labelledDateControls);

    const carrierCount = Math.max(
      controlNearLabel(
        ['歸戶載具列表', '歸戶載具'],
        'select,[role="combobox"],input,button'
      ),
      uniqueCount(cssElements([
        'select[name*="carrier" i]',
        '[role="combobox"][aria-label*="歸戶"]',
        '[aria-label*="載具"]',
      ]))
    );

    const capabilities = {
      startDate: effectiveDateCount > 0 ? 1 : 0,
      endDate: effectiveDateCount > 0 ? 1 : 0,
      carrierSelector: carrierCount > 0 ? 1 : 0,
      invoiceStatusSelector: Math.min(1, controlNearLabel(
        ['發票狀態'], 'select,[role="combobox"],input,button'
      )),
      buyerIdentifierInput: Math.min(1, controlNearLabel(
        ['買方統編'], 'input,[role="textbox"]'
      )),
      itemKeywordInput: Math.min(1, controlNearLabel(
        ['品名關鍵字'], 'input,[role="textbox"]'
      )),
      queryButton: Math.min(1, buttonTextCount(['查詢'])),
      clearButton: Math.min(1, buttonTextCount(['清除'])),
      pageSizeSelector: Math.min(1, uniqueCount(cssElements([
        'select[name*="page" i]',
        'select[id*="page" i]',
        '[role="combobox"][aria-label*="每頁"]',
        '.pagination select',
        '[class*="pagination"] select',
      ]))),
      currentPageIndicator: Math.min(1, uniqueCount(cssElements([
        '[aria-current="page"]',
        '.pagination .active',
        '[class*="pagination"] [class*="active"]',
      ]))),
      totalPageIndicator: Math.min(1, uniqueCount(cssElements([
        '.pagination',
        '[class*="pagination"]',
        '[aria-label*="頁碼"]',
      ]))),
      totalRowIndicator: Math.min(1, Array.from(document.querySelectorAll(
        'h1,h2,h3,h4,p,span,div'
      )).filter((element) => /共\\s*\\d+\\s*筆/.test(element.textContent || '')).length),
      resultTable: Math.min(1, Math.max(
        uniqueCount(cssElements(['table', '[role="table"]', '.table-responsive'])),
        ['發票號碼', '發票金額', '發票日期'].every(headerFound) ? 1 : 0
      )),
    };

    const pageSizes = new Set();
    for (const element of cssElements([
      'select[name*="page" i]',
      'select[id*="page" i]',
      '.pagination select',
      '[class*="pagination"] select',
    ])) {
      if (!(element instanceof HTMLSelectElement)) continue;
      for (const option of element.options) {
        const candidate = Number.parseInt(
          String(option.value || option.textContent || '').trim(),
          10,
        );
        if (Number.isInteger(candidate) && candidate > 0 && candidate <= 1000) {
          pageSizes.add(candidate);
        }
      }
    }

    const headers = {};
    for (const expectedHeader of expectedHeaders) {
      headers[expectedHeader] = headerFound(expectedHeader);
    }

    return JSON.stringify({
      schemaVersion,
      probeSucceeded: true,
      routeApproved,
      capabilities,
      availablePageSizes: Array.from(pageSizes).sort((a, b) => a - b),
      headers,
      errorCode: null,
    });
  } catch (_) {
    return JSON.stringify({
      schemaVersion,
      probeSucceeded: false,
      routeApproved: false,
      capabilities: {},
      availablePageSizes: [],
      headers: {},
      errorCode: 'PROBE_EXECUTION_FAILED',
    });
  }
})()
''';
}

String buildOfficialMobileViewportCompatibilityScript() {
  return '''
(() => {
  try {
    let viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) {
      viewport = document.createElement('meta');
      viewport.name = 'viewport';
      document.head.appendChild(viewport);
    }
    viewport.content =
      'width=device-width, initial-scale=0.86, minimum-scale=0.5, ' +
      'maximum-scale=5.0, user-scalable=yes';
    document.documentElement.style.overflowX = 'auto';
    document.documentElement.style.webkitTextSizeAdjust = '100%';
    if (document.body) {
      document.body.style.overflowX = 'auto';
      document.body.style.maxWidth = 'none';
    }
    for (const element of document.querySelectorAll(
      'main,form,table,.table-responsive,[class*="table"],[class*="result"]'
    )) {
      if (element.scrollWidth > document.documentElement.clientWidth) {
        element.style.maxWidth = 'none';
        element.style.overflowX = 'auto';
        element.style.webkitOverflowScrolling = 'touch';
      }
    }
    return 'VIEWPORT_COMPATIBILITY_APPLIED';
  } catch (_) {
    return 'VIEWPORT_COMPATIBILITY_FAILED';
  }
})()
''';
}
