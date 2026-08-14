import 'dart:convert';

import 'authenticated_selector_capability_probe.dart';
import 'official_invoice_detail_enrichment.dart';

String buildOfficialInvoiceDetailTargetInspectionScript() {
  final origin = jsonEncode(approvedCloudInvoiceQueryOrigin);
  final path = jsonEncode(approvedCloudInvoiceQueryPath);
  return '''
(() => {
  const approvedOrigin = $origin;
  const approvedPath = $path;
  const routePrefix = '/portal/btc/mobile/btc502w';
  const profile = $officialInvoiceDetailSelectorProfileVersion;
  const normalize = (value) =>
    String(value || '').replace(/[\\s＊*：:]/g, '').trim();
  const rendered = (element) => {
    if (!element || !element.isConnected) return false;
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      Number(style.opacity || '1') > 0 &&
      rect.width > 0 &&
      rect.height > 0;
  };
  const parseNumber = (value) => {
    const cleaned = String(value || '')
      .replace(/,/g, '')
      .replace(/[^0-9.\\-]/g, '');
    if (!cleaned || cleaned === '-' || cleaned === '.') return null;
    const number = Number(cleaned);
    return Number.isFinite(number) ? number : null;
  };
  const checked = (element) => {
    if (!element || !element.isConnected) return false;
    if (element.checked === true) return true;
    if (element.matches && element.matches(':checked')) return true;
    if (element.getAttribute('aria-checked') === 'true') return true;
    if (element.getAttribute('data-state') === 'checked') return true;
    const className = String(element.className || '').toLowerCase();
    return className.split(' ').some((token) =>
      ['checked', 'is-checked', 'selected'].includes(token)
    );
  };
  const routeApproved = window.location.origin === approvedOrigin && (
    window.location.pathname === approvedPath ||
    window.location.pathname === routePrefix ||
    window.location.pathname.startsWith(routePrefix + '/')
  );
  if (!routeApproved) {
    return JSON.stringify({
      routeApproved: false,
      selectorProfileVersion: profile,
      targets: [],
      errorCode: 'DETAIL_ROUTE_REJECTED'
    });
  }

  const headersOf = (table) => Array.from(
    table.querySelectorAll('th,[role="columnheader"],thead td')
  ).filter(rendered).map((element) => normalize(element.textContent));
  const indexOfHeader = (headers, labels) => headers.findIndex((header) =>
    labels.some((label) => header.includes(normalize(label)))
  );
  const dataRowsOf = (table) => Array.from(
    table.querySelectorAll('tbody tr,[role="row"]')
  ).filter((row) =>
    rendered(row) &&
    !row.closest('thead') &&
    !row.querySelector('[role="columnheader"]')
  );
  const cellTextAt = (row, index) => {
    const cells = Array.from(
      row.querySelectorAll('td,[role="gridcell"],[role="cell"]')
    );
    return index >= 0 && index < cells.length
      ? String(cells[index].textContent || '').trim()
      : '';
  };

  try {
    const tables = Array.from(
      document.querySelectorAll('table,[role="table"],[role="grid"]')
    ).filter(rendered);
    const table = tables.find((candidate) => {
      const headers = headersOf(candidate);
      return indexOfHeader(headers, ['發票號碼']) >= 0 &&
        indexOfHeader(headers, ['發票金額', '金額']) >= 0 &&
        indexOfHeader(headers, ['發票日期']) >= 0;
    }) || tables.find((candidate) => {
      const text = normalize(candidate.textContent);
      return text.includes('發票號碼') &&
        text.includes('發票金額') &&
        text.includes('發票日期');
    });
    if (!table) {
      return JSON.stringify({
        routeApproved: true,
        selectorProfileVersion: profile,
        targets: [],
        errorCode: 'DETAIL_RESULT_TABLE_NOT_FOUND'
      });
    }

    const headers = headersOf(table);
    const invoiceIndex = indexOfHeader(headers, ['發票號碼']);
    const amountIndex = indexOfHeader(headers, ['發票金額', '金額']);
    const sellerIdIndex = indexOfHeader(
      headers,
      ['賣方統一編號', '賣方統編']
    );
    const sellerNameIndex = indexOfHeader(headers, ['賣方名稱']);
    const targets = [];
    for (const row of dataRowsOf(table)) {
      const rowText = String(row.textContent || '');
      const invoiceCandidate =
        invoiceIndex >= 0 ? cellTextAt(row, invoiceIndex) : rowText;
      const match = invoiceCandidate.toUpperCase().match(/[A-Z]{2}\\d{8}/);
      if (!match) continue;
      const boxes = Array.from(
        row.querySelectorAll('input[type="checkbox"],[role="checkbox"]')
      );
      targets.push({
        invoiceNumber: match[0],
        selected: boxes.some(checked),
        expectedTotal:
          amountIndex >= 0 ? parseNumber(cellTextAt(row, amountIndex)) : null,
        sellerIdentifier:
          sellerIdIndex >= 0
            ? cellTextAt(row, sellerIdIndex).replace(/\\D/g, '')
            : '',
        sellerName:
          sellerNameIndex >= 0 ? cellTextAt(row, sellerNameIndex) : ''
      });
    }

    targets.sort((left, right) =>
      Number(right.selected) - Number(left.selected)
    );
    return JSON.stringify({
      routeApproved: true,
      selectorProfileVersion: profile,
      targets,
      errorCode:
        targets.length > 0 ? null : 'DETAIL_INVOICE_LINKS_NOT_FOUND'
    });
  } catch (_) {
    return JSON.stringify({
      routeApproved: true,
      selectorProfileVersion: profile,
      targets: [],
      errorCode: 'DETAIL_TARGET_INSPECTION_FAILED'
    });
  }
})()
''';
}

String buildOfficialInvoiceDetailEnrichmentScript({
  required OfficialInvoiceDetailSelectionScope scope,
  required String handlerName,
  String? singleInvoiceNumber,
}) {
  final origin = jsonEncode(approvedCloudInvoiceQueryOrigin);
  final path = jsonEncode(approvedCloudInvoiceQueryPath);
  final handler = jsonEncode(handlerName);
  final scopeName = jsonEncode(scope.name);
  final single = jsonEncode(singleInvoiceNumber?.trim().toUpperCase());
  return '''
(() => {
  const approvedOrigin = $origin;
  const approvedPath = $path;
  const routePrefix = '/portal/btc/mobile/btc502w';
  const handlerName = $handler;
  const scope = $scopeName;
  const requestedSingle = $single;
  const profile = $officialInvoiceDetailSelectorProfileVersion;
  const stateKey = '__mfaOfficialDetailEnrichmentState';
  const lifecycleKey = '__mfaOfficialDetailLifecycleInstalled';
  window[stateKey] = {
    cancelled: false,
    active: true,
    hostPaused: false,
    pauseStartedAt: null,
    pausedDurationMs: 0
  };
  const markHostPaused = () => {
    const state = window[stateKey];
    if (!state || state.active !== true || state.hostPaused) return;
    state.hostPaused = true;
    state.pauseStartedAt = Date.now();
  };
  const markHostResumed = () => {
    const state = window[stateKey];
    if (!state || state.active !== true || !state.hostPaused) return;
    const startedAt = Number(state.pauseStartedAt || Date.now());
    state.pausedDurationMs = Number(state.pausedDurationMs || 0) +
      Math.max(0, Date.now() - startedAt);
    state.pauseStartedAt = null;
    state.hostPaused = false;
  };
  const syncHostVisibility = () => {
    if (document.hidden || document.visibilityState !== 'visible') {
      markHostPaused();
    } else {
      markHostResumed();
    }
  };
  if (!window[lifecycleKey]) {
    document.addEventListener('visibilitychange', syncHostVisibility);
    window.addEventListener('pagehide', markHostPaused);
    window.addEventListener('pageshow', syncHostVisibility);
    window[lifecycleKey] = true;
  }
  syncHostVisibility();

  const send = (payload) => {
    try {
      window.flutter_inappwebview.callHandler(handlerName, payload);
    } catch (_) {}
  };
  const sleep = (milliseconds) =>
    new Promise((resolve) => window.setTimeout(resolve, milliseconds));
  const normalize = (value) =>
    String(value || '').replace(/[\\s＊*：:]/g, '').trim();
  const rendered = (element) => {
    if (!element || !element.isConnected) return false;
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      Number(style.opacity || '1') > 0 &&
      rect.width > 0 &&
      rect.height > 0;
  };
  const parseNumber = (value) => {
    const cleaned = String(value || '')
      .replace(/,/g, '')
      .replace(/[^0-9.\\-]/g, '');
    if (!cleaned || cleaned === '-' || cleaned === '.') return null;
    const number = Number(cleaned);
    return Number.isFinite(number) ? number : null;
  };
  const checked = (element) => {
    if (!element || !element.isConnected) return false;
    if (element.checked === true) return true;
    if (element.matches && element.matches(':checked')) return true;
    if (element.getAttribute('aria-checked') === 'true') return true;
    if (element.getAttribute('data-state') === 'checked') return true;
    const className = String(element.className || '').toLowerCase();
    return className.split(' ').some((token) =>
      ['checked', 'is-checked', 'selected'].includes(token)
    );
  };
  const routeApproved = window.location.origin === approvedOrigin && (
    window.location.pathname === approvedPath ||
    window.location.pathname === routePrefix ||
    window.location.pathname.startsWith(routePrefix + '/')
  );
  if (!routeApproved) {
    send({
      type: 'complete',
      requestedCount: 0,
      cancelled: false,
      errorCode: 'DETAIL_ROUTE_REJECTED'
    });
    return;
  }

  const headersOf = (table) => Array.from(
    table.querySelectorAll('th,[role="columnheader"],thead td')
  ).filter(rendered).map((element) => normalize(element.textContent));
  const indexOfHeader = (headers, labels) => headers.findIndex((header) =>
    labels.some((label) => header.includes(normalize(label)))
  );
  const allRowsOf = (table) => Array.from(
    table.querySelectorAll('tr,[role="row"]')
  ).filter(rendered);
  const cellsOf = (row) => Array.from(
    row.querySelectorAll(
      'th,td,[role="columnheader"],[role="gridcell"],[role="cell"]'
    )
  ).filter(rendered);
  const dataRowsOf = (table) => Array.from(
    table.querySelectorAll('tbody tr,[role="row"]')
  ).filter((row) =>
    rendered(row) &&
    !row.closest('thead') &&
    !row.querySelector('[role="columnheader"]')
  );
  const cellTextAt = (row, index) => {
    const cells = cellsOf(row);
    return index >= 0 && index < cells.length
      ? String(cells[index].textContent || '').trim()
      : '';
  };
  const tableProfile = (table) => {
    let headers = headersOf(table);
    let rows = dataRowsOf(table);
    if (headers.length === 0) {
      const allRows = allRowsOf(table);
      if (allRows.length > 0) {
        headers = cellsOf(allRows[0]).map((cell) => normalize(cell.textContent));
        rows = allRows.slice(1).filter((row) => cellsOf(row).length > 0);
      }
    }
    return { headers, rows };
  };
  const findResultTable = () => Array.from(
    document.querySelectorAll('table,[role="table"],[role="grid"]')
  ).filter(rendered).find((candidate) => {
    const profileData = tableProfile(candidate);
    return indexOfHeader(profileData.headers, ['發票號碼']) >= 0 &&
      indexOfHeader(profileData.headers, ['發票金額', '金額']) >= 0 &&
      indexOfHeader(profileData.headers, ['發票日期']) >= 0;
  }) || null;

  const table = findResultTable();
  if (!table) {
    send({
      type: 'complete',
      requestedCount: 0,
      cancelled: false,
      errorCode: 'DETAIL_RESULT_TABLE_NOT_FOUND'
    });
    return;
  }

  const resultProfile = tableProfile(table);
  const headers = resultProfile.headers;
  const invoiceIndex = indexOfHeader(headers, ['發票號碼']);
  const amountIndex = indexOfHeader(headers, ['發票金額', '金額']);
  const sellerIdIndex = indexOfHeader(
    headers,
    ['賣方統一編號', '賣方統編']
  );
  const sellerNameIndex = indexOfHeader(headers, ['賣方名稱']);
  const targets = [];

  for (const row of resultProfile.rows) {
    const rowText = String(row.textContent || '');
    const invoiceCandidate =
      invoiceIndex >= 0 ? cellTextAt(row, invoiceIndex) : rowText;
    const match = invoiceCandidate.toUpperCase().match(/[A-Z]{2}\\d{8}/);
    if (!match) continue;
    const invoiceNumber = match[0];
    const boxes = Array.from(
      row.querySelectorAll('input[type="checkbox"],[role="checkbox"]')
    );
    const selected = boxes.some(checked);
    if (scope === 'singleInvoice' && invoiceNumber !== requestedSingle) {
      continue;
    }
    if (scope === 'selectedInvoices' && !selected) continue;

    const candidates = Array.from(
      row.querySelectorAll('a,button,[role="button"]')
    ).filter(rendered);
    const link = candidates.find((element) =>
      normalize(element.textContent).includes(invoiceNumber)
    ) || (() => {
      const textNode = Array.from(row.querySelectorAll('*')).find((element) =>
        rendered(element) &&
        normalize(element.textContent) === invoiceNumber
      );
      return textNode
        ? textNode.closest('a,button,[role="button"]')
        : null;
    })();

    targets.push({
      row,
      link,
      invoiceNumber,
      expectedTotal:
        amountIndex >= 0 ? parseNumber(cellTextAt(row, amountIndex)) : null,
      expectedSellerIdentifier:
        sellerIdIndex >= 0
          ? cellTextAt(row, sellerIdIndex).replace(/\\D/g, '')
          : '',
      expectedSellerName:
        sellerNameIndex >= 0 ? cellTextAt(row, sellerNameIndex) : ''
    });
  }

  const dialogSelector = [
    '[role="dialog"]',
    'dialog[open]',
    '.modal.show',
    '.modal.in',
    '.modal[style*="display: block"]',
    '.modal[style*="display:block"]',
    '.ui-dialog',
    '.bootbox',
    '.swal2-popup',
    '.mat-dialog-container',
    '.p-dialog',
    '.ant-modal'
  ].join(',');
  const dialogRoots = () => {
    const roots = Array.from(document.querySelectorAll(dialogSelector))
      .filter(rendered);
    const titleNodes = Array.from(document.querySelectorAll(
      'h1,h2,h3,h4,h5,.modal-title,.ui-dialog-title,[class*="title"]'
    )).filter((node) =>
      rendered(node) && normalize(node.textContent).includes('發票明細')
    );
    for (const node of titleNodes) {
      const root = node.closest(dialogSelector) || node.parentElement;
      if (root && rendered(root) && !roots.includes(root)) roots.push(root);
    }
    return roots;
  };
  const dialogScore = (dialog, invoiceNumber) => {
    const text = normalize(dialog.textContent).toUpperCase();
    let score = 0;
    if (text.includes(invoiceNumber)) score += 100;
    if (text.includes('發票明細')) score += 40;
    if (text.includes('消費明細')) score += 30;
    score += Math.min(dialog.querySelectorAll('table').length, 4) * 5;
    return score;
  };
  const findDetailDialog = (invoiceNumber) => {
    const roots = dialogRoots()
      .map((dialog) => ({ dialog, score: dialogScore(dialog, invoiceNumber) }))
      .filter((item) => item.score >= 40)
      .sort((left, right) => right.score - left.score);
    return roots.length > 0 ? roots[0].dialog : null;
  };
  const waitUntilHostVisible = async () => {
    while (window[stateKey] && window[stateKey].hostPaused) {
      if (window[stateKey].cancelled) return false;
      await sleep(120);
    }
    return true;
  };
  const waitFor = async (predicate, timeoutMs) => {
    const startedAt = Date.now();
    const initialPausedDuration = Number(
      window[stateKey] && window[stateKey].pausedDurationMs || 0
    );
    while (true) {
      const state = window[stateKey];
      if (state && state.cancelled) return null;
      if (state && state.hostPaused) {
        const resumed = await waitUntilHostVisible();
        if (!resumed) return null;
        continue;
      }
      const pausedDuration = Math.max(
        0,
        Number(state && state.pausedDurationMs || 0) -
          initialPausedDuration
      );
      const activeElapsed = Date.now() - startedAt - pausedDuration;
      if (activeElapsed >= timeoutMs) return null;
      const value = predicate();
      if (value) return value;
      await sleep(120);
    }
  };
  const hasLoadingMask = (root) => Array.from(root.querySelectorAll(
    '[aria-busy="true"],.loading,.loading-mask,.blockUI,.spinner,.spinner-border,.fa-spinner'
  )).some(rendered);
  const findLabelValue = (root, labels) => {
    const accepted = labels.map(normalize);
    const rows = Array.from(root.querySelectorAll('tr,li,dl,div,p'));
    for (const row of rows) {
      if (!rendered(row)) continue;
      const cells = Array.from(row.children).filter(rendered);
      if (cells.length >= 2) {
        const labelText = normalize(cells[0].textContent);
        if (accepted.some((label) => labelText.includes(label))) {
          return String(cells[1].textContent || '').trim();
        }
      }
    }
    const candidates = Array.from(
      root.querySelectorAll('dt,dd,label,span,strong,b')
    );
    for (const node of candidates) {
      if (!rendered(node)) continue;
      const compact = normalize(node.textContent);
      if (!accepted.some((label) => compact.includes(label))) continue;
      const sibling = node.nextElementSibling;
      if (sibling && rendered(sibling)) {
        return String(sibling.textContent || '').trim();
      }
    }
    return '';
  };
  const findOfficialTax = (root) => {
    const accepted = ['營業稅額', '稅額', '稅'].map(normalize);
    const rows = Array.from(root.querySelectorAll('tr,li,dl,div,p'));
    for (const row of rows) {
      if (!rendered(row)) continue;
      const cells = Array.from(row.children).filter(rendered);
      if (cells.length < 2) continue;
      const label = normalize(cells[0].textContent);
      if (!accepted.includes(label)) continue;
      return {
        label,
        value: String(cells[1].textContent || '').trim()
      };
    }
    const candidates = Array.from(
      root.querySelectorAll('dt,label,span,strong,b')
    );
    for (const node of candidates) {
      if (!rendered(node)) continue;
      const label = normalize(node.textContent);
      if (!accepted.includes(label)) continue;
      const sibling = node.nextElementSibling;
      if (sibling && rendered(sibling)) {
        return {
          label,
          value: String(sibling.textContent || '').trim()
        };
      }
    }
    return null;
  };
  const parseTimestamp = (value) => {
    const match = String(value || '').match(
      /(20\\d{2})\\s*[年\\/-]\\s*(\\d{1,2})\\s*[月\\/-]\\s*(\\d{1,2})\\s*日?\\s*[T ]\\s*(\\d{1,2}):(\\d{2})(?::(\\d{2}))?/
    );
    if (!match) return null;
    const pad = (part) => String(part).padStart(2, '0');
    return match[1] + '-' +
      pad(match[2]) + '-' +
      pad(match[3]) + 'T' +
      pad(match[4]) + ':' +
      pad(match[5]) + ':' +
      pad(match[6] || '00');
  };
  const parseCurrency = (root, rootText) => {
    const labelled = findLabelValue(root, ['幣別', '交易幣別']);
    const labelledMatch = labelled.toUpperCase().match(
      /\\b(TWD|USD|JPY|EUR|CNY|HKD|KRW|GBP|AUD|CAD|SGD)\\b/
    );
    if (labelledMatch) return labelledMatch[1];
    const general = String(rootText || '').toUpperCase().match(
      /\\b(TWD|USD|JPY|EUR|CNY|HKD|KRW|GBP|AUD|CAD|SGD)\\b/
    );
    return general ? general[1] : null;
  };

  const findSummaryTable = (dialog) => Array.from(
    dialog.querySelectorAll('table,[role="table"],[role="grid"]')
  ).filter(rendered).find((candidate) => {
    const profileData = tableProfile(candidate);
    return indexOfHeader(profileData.headers, ['發票日期']) >= 0 &&
      indexOfHeader(profileData.headers, ['金額', '發票金額']) >= 0 &&
      (
        indexOfHeader(profileData.headers, ['發票狀態', '狀態']) >= 0 ||
        indexOfHeader(profileData.headers, ['賣方統一編號', '賣方統編']) >= 0 ||
        indexOfHeader(profileData.headers, ['賣方名稱']) >= 0
      );
  }) || null;
  const findItemTable = (dialog) => Array.from(
    dialog.querySelectorAll('table,[role="table"],[role="grid"]')
  ).filter(rendered).find((candidate) => {
    const profileData = tableProfile(candidate);
    return indexOfHeader(profileData.headers, ['品名', '商品名稱']) >= 0 &&
      indexOfHeader(profileData.headers, ['金額', '小計']) >= 0;
  }) || null;
  const extractSummary = (table) => {
    if (!table) return null;
    const profileData = tableProfile(table);
    if (profileData.rows.length === 0) return null;
    const row = profileData.rows[0];
    const value = (labels) => {
      const index = indexOfHeader(profileData.headers, labels);
      return index >= 0 ? cellTextAt(row, index) : '';
    };
    return {
      timestampText: value(['發票日期', '開立時間', '交易時間']),
      totalText: value(['金額', '發票金額', '總計', '總金額']),
      statusText: value(['發票狀態', '狀態']),
      sellerIdentifierText: value(['賣方統一編號', '賣方統編']),
      sellerNameText: value(['賣方名稱']),
      sellerAddressText: value(['賣方地址'])
    };
  };
  const extractLineItems = (table) => {
    if (!table) return [];
    const profileData = tableProfile(table);
    const nameIndex = indexOfHeader(
      profileData.headers,
      ['品名', '商品名稱']
    );
    const quantityIndex = indexOfHeader(profileData.headers, ['數量']);
    const unitPriceIndex = indexOfHeader(profileData.headers, ['單價']);
    const itemAmountIndex = indexOfHeader(
      profileData.headers,
      ['金額', '小計']
    );
    const output = [];
    for (const row of profileData.rows) {
      const name = cellTextAt(row, nameIndex);
      const amount = parseNumber(cellTextAt(row, itemAmountIndex));
      if (!name || amount === null) continue;
      output.push({
        name,
        quantity: parseNumber(cellTextAt(row, quantityIndex)),
        unitPrice: parseNumber(cellTextAt(row, unitPriceIndex)),
        amount
      });
    }
    return output;
  };
  const waitForDialogReady = async (invoiceNumber) => waitFor(() => {
    const dialog = findDetailDialog(invoiceNumber);
    if (!dialog || hasLoadingMask(dialog)) return null;
    const text = String(dialog.textContent || '').toUpperCase();
    if (!text.includes(invoiceNumber)) return null;
    const summaryTable = findSummaryTable(dialog);
    const itemTable = findItemTable(dialog);
    if (!summaryTable || !itemTable) return null;
    const itemRows = tableProfile(itemTable).rows;
    if (itemRows.length === 0) return null;
    return { dialog, summaryTable, itemTable };
  }, 15000);
  const closeDialog = async (dialog) => {
    const controls = Array.from(
      dialog.querySelectorAll(
        'button,a,[role="button"],input[type="button"]'
      )
    ).filter(rendered);
    const close = controls.find((element) => {
      const text = normalize(
        element.textContent ||
        element.value ||
        element.getAttribute('aria-label') ||
        element.getAttribute('title')
      ).toLowerCase();
      return text === '關閉' ||
        text === '取消' ||
        text === 'close' ||
        text === '×' ||
        text === 'x';
    }) || dialog.querySelector(
      '.btn-close,.close,[data-dismiss="modal"],[aria-label="Close"],[aria-label="關閉"]'
    );
    if (close) close.click();
    await waitFor(() => !rendered(dialog), 4000);
  };

  send({ type: 'started', total: targets.length });
  (async () => {
    for (let index = 0; index < targets.length; index += 1) {
      if (window[stateKey] && window[stateKey].cancelled) break;
      const target = targets[index];
      send({
        type: 'progress',
        current: index + 1,
        total: targets.length,
        invoiceNumber: target.invoiceNumber,
        message: '正在開啟並等待官方發票明細載入'
      });

      const base = {
        requestedInvoiceNumber: target.invoiceNumber,
        invoiceNumber: '',
        selectorProfileVersion: profile,
        fetchedAt: new Date().toISOString(),
        success: false,
        invoiceIdentityMatches: false,
        detailTotalInternallyConsistent: false,
        detailTotalMatchesCsv: false,
        sellerIdentifierConsistent: true,
        lineItems: [],
        exactTimestamp: null,
        currencyCode: null,
        officialStatus: null,
        sellerIdentifier: null,
        sellerName: null,
        expectedTotal: target.expectedTotal,
        detailTotal: null,
        officialTaxAmount: null,
        officialTaxLabel: null,
        lineItemSubtotal: null,
        unallocatedDifference: null,
        errorCode: null,
        dialogDetected: false,
        summaryTableDetected: false,
        itemTableDetected: false,
        detectedItemRowCount: 0
      };

      if (!target.link) {
        base.errorCode = 'DETAIL_LINK_NOT_FOUND';
        send({ type: 'result', result: base });
        continue;
      }

      try {
        target.link.click();
      } catch (_) {
        base.errorCode = 'DETAIL_LINK_CLICK_FAILED';
        send({ type: 'result', result: base });
        continue;
      }

      const firstDialog = await waitFor(
        () => findDetailDialog(target.invoiceNumber),
        6000
      );
      if (!firstDialog) {
        base.errorCode =
          window[stateKey] && window[stateKey].cancelled
            ? 'DETAIL_CANCELLED'
            : 'DETAIL_NO_DIALOG';
        send({ type: 'result', result: base });
        continue;
      }
      base.dialogDetected = true;

      const ready = await waitForDialogReady(target.invoiceNumber);
      if (!ready) {
        if (window[stateKey] && window[stateKey].cancelled) {
          base.errorCode = 'DETAIL_CANCELLED';
        } else {
          const summaryTable = findSummaryTable(firstDialog);
          const itemTable = findItemTable(firstDialog);
          base.summaryTableDetected = !!summaryTable;
          base.itemTableDetected = !!itemTable;
          base.detectedItemRowCount = itemTable
            ? tableProfile(itemTable).rows.length
            : 0;
          base.errorCode = !summaryTable
            ? 'DETAIL_REQUIRED_FIELD_MISSING'
            : !itemTable
              ? 'DETAIL_ITEM_TABLE_NOT_FOUND'
              : 'DETAIL_RENDER_TIMEOUT';
        }
        send({ type: 'result', result: base });
        await closeDialog(firstDialog);
        continue;
      }

      const dialog = ready.dialog;
      const summaryTable = ready.summaryTable;
      const itemTable = ready.itemTable;
      base.summaryTableDetected = true;
      base.itemTableDetected = true;

      const text = String(dialog.textContent || '');
      const summary = extractSummary(summaryTable);
      const invoiceMatch = text.toUpperCase().match(/[A-Z]{2}\\d{8}/);
      base.invoiceNumber = invoiceMatch ? invoiceMatch[0] : '';
      base.invoiceIdentityMatches =
        base.invoiceNumber === target.invoiceNumber;
      base.exactTimestamp = parseTimestamp(
        summary && summary.timestampText ? summary.timestampText : text
      );
      base.currencyCode = parseCurrency(dialog, text);
      base.officialStatus = (
        summary && summary.statusText
          ? summary.statusText
          : findLabelValue(dialog, ['發票狀態', '狀態'])
      ) || null;

      const sellerIdText = summary && summary.sellerIdentifierText
        ? summary.sellerIdentifierText
        : findLabelValue(dialog, ['賣方統一編號', '賣方統編']);
      const sellerIdMatch = String(sellerIdText || '').match(/\\d{8}/);
      base.sellerIdentifier = sellerIdMatch ? sellerIdMatch[0] : null;
      base.sellerName = (
        summary && summary.sellerNameText
          ? summary.sellerNameText
          : findLabelValue(dialog, ['賣方名稱'])
      ) || null;

      const totalText = summary && summary.totalText
        ? summary.totalText
        : findLabelValue(
            dialog,
            ['發票金額', '總計', '總金額', '金額']
          );
      base.detailTotal = parseNumber(totalText);
      const productItems = extractLineItems(itemTable);
      base.detectedItemRowCount = productItems.length;
      base.lineItemSubtotal = productItems.reduce(
        (sum, item) => sum + item.amount,
        0
      );

      const taxField = findOfficialTax(dialog);
      base.officialTaxLabel = taxField ? taxField.label : null;
      base.officialTaxAmount = taxField
        ? parseNumber(taxField.value)
        : null;
      base.lineItems = productItems.slice();

      if (base.detailTotal !== null && productItems.length > 0) {
        if (base.officialTaxAmount !== null) {
          base.unallocatedDifference =
            base.detailTotal -
            base.lineItemSubtotal -
            base.officialTaxAmount;
          base.detailTotalInternallyConsistent =
            base.officialTaxAmount >= 0 &&
            Math.abs(base.unallocatedDifference) <= 0.01;
          if (
            base.detailTotalInternallyConsistent &&
            Math.abs(base.officialTaxAmount) > 0.005
          ) {
            base.lineItems.push({
              name: '官方稅額',
              quantity: 1,
              unitPrice: base.officialTaxAmount,
              amount: base.officialTaxAmount
            });
          }
        } else {
          base.unallocatedDifference =
            base.detailTotal - base.lineItemSubtotal;
          base.detailTotalInternallyConsistent =
            Math.abs(base.unallocatedDifference) <= 0.01;
        }
      }

      base.detailTotalMatchesCsv =
        target.expectedTotal !== null &&
        base.detailTotal !== null &&
        Math.abs(target.expectedTotal - base.detailTotal) <= 0.01;
      base.sellerIdentifierConsistent =
        !target.expectedSellerIdentifier ||
        !base.sellerIdentifier ||
        target.expectedSellerIdentifier === base.sellerIdentifier;

      base.success =
        base.invoiceIdentityMatches &&
        base.detailTotalInternallyConsistent &&
        base.detailTotalMatchesCsv &&
        base.exactTimestamp !== null &&
        base.lineItems.length > 0;

      if (!base.success) {
        base.errorCode = !base.invoiceIdentityMatches
          ? 'DETAIL_INVOICE_IDENTITY_MISMATCH'
          : productItems.length === 0
            ? 'DETAIL_ITEM_ROW_PARSE_FAILED'
            : !base.detailTotalInternallyConsistent
              ? base.officialTaxAmount !== null
                ? 'DETAIL_OFFICIAL_TAX_MISMATCH'
                : 'DETAIL_UNALLOCATED_DIFFERENCE'
              : !base.detailTotalMatchesCsv
                ? 'DETAIL_TOTAL_CSV_MISMATCH'
                : base.exactTimestamp === null
                  ? 'DETAIL_TIMESTAMP_NOT_FOUND'
                  : 'DETAIL_REQUIRED_FIELD_MISSING';
      }

      send({ type: 'result', result: base });
      await closeDialog(dialog);
      await sleep(650);
    }

    const cancelled = !!(
      window[stateKey] && window[stateKey].cancelled
    );
    if (window[stateKey]) window[stateKey].active = false;
    send({
      type: 'complete',
      requestedCount: targets.length,
      cancelled,
      errorCode: cancelled
        ? 'DETAIL_CANCELLED'
        : targets.length === 0
          ? 'DETAIL_SCOPE_EMPTY'
          : null
    });
  })().catch(() => {
    if (window[stateKey]) window[stateKey].active = false;
    send({
      type: 'complete',
      requestedCount: targets.length,
      cancelled: false,
      errorCode: 'DETAIL_BATCH_FAILED'
    });
  });
})()
''';
}

String buildOfficialInvoiceDetailCancellationScript() => r'''
(() => {
  const state = window.__mfaOfficialDetailEnrichmentState;
  if (state && typeof state === 'object') state.cancelled = true;
  return true;
})()
''';
