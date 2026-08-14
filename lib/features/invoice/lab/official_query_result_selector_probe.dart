import 'dart:convert';

import 'authenticated_selector_capability_probe.dart';

/// Builds the LAB-only structural probe used after the result-layout parity
/// patch. The `resultTable` capability is reported as available only when the
/// visible result structure includes the required result columns, row
/// selection, header select-all, and the CSV download control.
String buildOfficialQueryResultSelectorProbeScript() {
  final encodedOrigin = jsonEncode(approvedCloudInvoiceQueryOrigin);
  final encodedPath = jsonEncode(approvedCloudInvoiceQueryPath);
  final encodedRoutePrefix = jsonEncode('/portal/btc/mobile/btc502w');
  final encodedHeaders = jsonEncode(expectedOfficialResultHeaders);

  return '''
(() => {
  const schemaVersion = $authenticatedSelectorProbeSchemaVersion;
  const approvedOrigin = $encodedOrigin;
  const approvedPath = $encodedPath;
  const approvedRoutePrefix = $encodedRoutePrefix;
  const expectedHeaders = $encodedHeaders;
  const completeResultHeaders = [
    '發票號碼',
    '發票金額',
    '發票日期',
    '捐贈日期',
    '買方統編',
  ];
  const isWhitespace = (character) => {
    const code = character.charCodeAt(0);
    return code === 9 || code === 10 || code === 13 || code === 32;
  };
  const normalize = (value) => Array.from(String(value || ''))
    .filter((character) => !isWhitespace(character))
    .join('')
    .replace(/[＊*：:]/g, '')
    .trim();
  const isRendered = (element) => {
    if (!element || !element.isConnected) return false;
    const style = window.getComputedStyle(element);
    if (style.display === 'none' || style.visibility === 'hidden') return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const uniqueCount = (elements) => new Set(
    elements.filter((element) => element && isRendered(element))
  ).size;
  const cssElements = (selectors, root = document) => {
    const output = [];
    for (const selector of selectors) {
      for (const element of root.querySelectorAll(selector)) output.push(element);
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
        (node.getAttribute && node.getAttribute('aria-label')) || node.textContent || ''
      );
      if (!normalizedLabels.some((label) => text.includes(label))) continue;
      if (node.htmlFor) output.push(document.getElementById(node.htmlFor));
      for (const element of node.querySelectorAll(controlSelector)) output.push(element);
      const parent = node.parentElement;
      if (parent) {
        for (const element of parent.querySelectorAll(controlSelector)) output.push(element);
      }
      const next = node.nextElementSibling;
      if (next && next.matches && next.matches(controlSelector)) output.push(next);
      if (next) {
        for (const element of next.querySelectorAll(controlSelector)) output.push(element);
      }
    }
    return uniqueCount(output);
  };
  const controlTextCount = (labels) => {
    const accepted = labels.map(normalize);
    return uniqueCount(
      Array.from(document.querySelectorAll(
        'button,a,input[type="button"],input[type="submit"],input[type="reset"],' +
        '[role="button"]'
      )).filter((element) => {
        const text = normalize(
          element.textContent || element.value || element.getAttribute('aria-label')
        );
        return accepted.includes(text);
      })
    );
  };
  const visibleHeaderCells = (root = document) => Array.from(root.querySelectorAll(
    'th,[role="columnheader"],thead td,.table-header,[class*="header"]'
  )).filter(isRendered);
  const normalizedHeaders = (root = document) =>
    visibleHeaderCells(root).map((node) => normalize(node.textContent));
  const headerFound = (header, root = document) => normalizedHeaders(root).some(
    (value) => value === normalize(header) || value.includes(normalize(header))
  );
  const findResultRoot = () => {
    const candidates = document.querySelectorAll(
      'table,[role="table"],[role="grid"],.table-responsive,' +
      '[class*="invoice-result"],[class*="query-result"]'
    );
    for (const root of candidates) {
      if (!isRendered(root)) continue;
      if (!completeResultHeaders.every((header) => headerFound(header, root))) continue;
      const selectionCount = uniqueCount(cssElements([
        'input[type="checkbox"]',
        '[role="checkbox"]',
      ], root));
      if (selectionCount > 0) return root;
    }
    return null;
  };
  const hasTotalRowText = (element) => {
    if (!isRendered(element)) return false;
    const compact = normalize(element.textContent || '');
    if (!compact.startsWith('共') || !compact.endsWith('筆')) return false;
    const value = Number.parseInt(compact.slice(1, -1), 10);
    return Number.isInteger(value) && value >= 0;
  };

  try {
    const currentPath = window.location.pathname;
    const routeApproved =
      window.location.origin === approvedOrigin &&
      (currentPath === approvedPath ||
       currentPath === approvedRoutePrefix ||
       currentPath.startsWith(approvedRoutePrefix + '/'));

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

    const resultRoot = findResultRoot();
    const completeHeadersVisible = resultRoot != null && completeResultHeaders.every(
      (header) => headerFound(header, resultRoot)
    );
    const rowSelectionCount = resultRoot == null ? 0 : uniqueCount(cssElements([
      'tbody input[type="checkbox"]',
      'tbody [role="checkbox"]',
      '[role="row"] input[type="checkbox"]',
      '[role="row"] [role="checkbox"]',
    ], resultRoot));
    const headerSelectionCount = resultRoot == null ? 0 : uniqueCount(cssElements([
      'thead input[type="checkbox"]',
      'thead [role="checkbox"]',
      'th input[type="checkbox"]',
      'th [role="checkbox"]',
      '[role="columnheader"] input[type="checkbox"]',
      '[role="columnheader"] [role="checkbox"]',
    ], resultRoot));
    const csvDownloadCount = controlTextCount(['下載CSV檔', '下載CSV']);
    const completeResultStructure =
      resultRoot != null &&
      completeHeadersVisible &&
      rowSelectionCount > 0 &&
      headerSelectionCount > 0 &&
      csvDownloadCount > 0;

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
      queryButton: Math.min(1, controlTextCount(['查詢'])),
      clearButton: Math.min(1, controlTextCount(['清除'])),
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
      )).filter(hasTotalRowText).length),
      resultTable: completeResultStructure ? 1 : 0,
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
          10
        );
        if (Number.isInteger(candidate) && candidate > 0 && candidate <= 1000) {
          pageSizes.add(candidate);
        }
      }
    }

    const headers = {};
    for (const expectedHeader of expectedHeaders) {
      headers[expectedHeader] = headerFound(expectedHeader, resultRoot || document);
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
