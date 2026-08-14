import 'dart:convert';

import 'authenticated_selector_capability_probe.dart';

class OfficialQueryPagePreparationResult {
  const OfficialQueryPagePreparationResult({
    required this.code,
    required this.routeApproved,
    required this.pageSizeControlFound,
    required this.pageSize100Requested,
    required this.pageSizeApplyControlFound,
    required this.pageSizeApplyTriggered,
    required this.pageSizeAlreadyApplied,
    required this.headerCheckboxFound,
    required this.headerCheckboxSelected,
    this.resultTableStable = false,
    this.exportRoleMapBuilt = false,
    this.exportCheckboxFound = false,
    this.exportCheckboxRoleAmbiguous = false,
    this.exportCheckboxSelected = false,
    this.visibleExportRowCount = 0,
    this.checkedExportRowCount = 0,
    this.exportButtonFound = false,
    this.exportButtonEnabled = false,
  });

  final String code;
  final bool routeApproved;
  final bool pageSizeControlFound;
  final bool pageSize100Requested;
  final bool pageSizeApplyControlFound;
  final bool pageSizeApplyTriggered;
  final bool pageSizeAlreadyApplied;
  final bool headerCheckboxFound;
  final bool headerCheckboxSelected;
  final bool resultTableStable;
  final bool exportRoleMapBuilt;
  final bool exportCheckboxFound;
  final bool exportCheckboxRoleAmbiguous;
  final bool exportCheckboxSelected;
  final int visibleExportRowCount;
  final int checkedExportRowCount;
  final bool exportButtonFound;
  final bool exportButtonEnabled;

  bool get pageSizeActionAccepted =>
      routeApproved &&
      pageSize100Requested &&
      (pageSizeApplyTriggered || pageSizeAlreadyApplied);

  bool get accepted =>
      exportReady || detailReady || pageSizeApplyTriggered;

  bool get detailReady =>
      code == 'DETAIL_PAGE_SIZE_READY' &&
      pageSizeActionAccepted &&
      resultTableStable;

  bool get exportReady =>
      code == 'CSV_EXPORT_READY' &&
      pageSizeActionAccepted &&
      resultTableStable &&
      exportRoleMapBuilt &&
      exportCheckboxFound &&
      !exportCheckboxRoleAmbiguous &&
      exportCheckboxSelected &&
      visibleExportRowCount > 0 &&
      checkedExportRowCount == visibleExportRowCount &&
      exportButtonFound &&
      exportButtonEnabled;

  factory OfficialQueryPagePreparationResult.fromRaw(Object? raw) {
    Object? decoded = raw;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return invalid;
      }
    }
    if (decoded is! Map) return invalid;

    final map = decoded;
    bool flag(String key) => map[key] == true;
    int count(String key) => (map[key] as num?)?.toInt() ?? 0;
    return OfficialQueryPagePreparationResult(
      code: map['code']?.toString() ?? 'PAGE_PREPARATION_RESPONSE_INVALID',
      routeApproved: flag('routeApproved'),
      pageSizeControlFound: flag('pageSizeControlFound'),
      pageSize100Requested: flag('pageSize100Requested'),
      pageSizeApplyControlFound: flag('pageSizeApplyControlFound'),
      pageSizeApplyTriggered: flag('pageSizeApplyTriggered'),
      pageSizeAlreadyApplied: flag('pageSizeAlreadyApplied'),
      headerCheckboxFound: flag('headerCheckboxFound'),
      headerCheckboxSelected: flag('headerCheckboxSelected'),
      resultTableStable: flag('resultTableStable'),
      exportRoleMapBuilt: flag('exportRoleMapBuilt'),
      exportCheckboxFound: flag('exportCheckboxFound'),
      exportCheckboxRoleAmbiguous: flag('exportCheckboxRoleAmbiguous'),
      exportCheckboxSelected: flag('exportCheckboxSelected'),
      visibleExportRowCount: count('visibleExportRowCount'),
      checkedExportRowCount: count('checkedExportRowCount'),
      exportButtonFound: flag('exportButtonFound'),
      exportButtonEnabled: flag('exportButtonEnabled'),
    );
  }

  static const invalid = OfficialQueryPagePreparationResult(
    code: 'PAGE_PREPARATION_RESPONSE_INVALID',
    routeApproved: false,
    pageSizeControlFound: false,
    pageSize100Requested: false,
    pageSizeApplyControlFound: false,
    pageSizeApplyTriggered: false,
    pageSizeAlreadyApplied: false,
    headerCheckboxFound: false,
    headerCheckboxSelected: false,
  );
}

abstract interface class OfficialQueryPagePreparationRuntime {
  Future<OfficialQueryPagePreparationResult> prepareCurrentPageForExport();
}

abstract interface class OfficialDetailPagePreparationRuntime {
  Future<OfficialQueryPagePreparationResult>
      prepareCurrentPageForOfficialDetail();
}

String buildOfficialQueryPagePreparationScript({
  bool prepareExportSelection = true,
}) {
  final origin = jsonEncode(approvedCloudInvoiceQueryOrigin);
  final path = jsonEncode(approvedCloudInvoiceQueryPath);
  const prefix = '/portal/btc/mobile/btc502w';
  final prepareExport = prepareExportSelection ? 'true' : 'false';

  return '''
(() => {
  const approvedOrigin = $origin;
  const approvedPath = $path;
  const approvedRoutePrefix = '$prefix';
  const clusterTolerance = 18;
  const headerTolerance = 30;
  const stableWindowMs = 700;
  const prepareExportSelection = $prepareExport;
  const applyStateKey = '__mfaPageSizeApplyIssuedAt';
  const stableStateKey = '__mfaCsvExportPreparationState';
  const normalize = (value) => String(value || '')
    .replace(/[\\s＊*：:]/g, '').trim();
  const rendered = (element) => {
    if (!element) return false;
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      rect.width > 0 && rect.height > 0;
  };
  const checked = (element) =>
    element.checked === true ||
    element.getAttribute('aria-checked') === 'true';
  const unique = (items) => Array.from(new Set(items));
  const routeApproved = window.location.origin === approvedOrigin &&
    (window.location.pathname === approvedPath ||
     window.location.pathname === approvedRoutePrefix ||
     window.location.pathname.startsWith(approvedRoutePrefix + '/'));
  const report = {
    code: routeApproved
      ? 'PAGE_PREPARATION_STARTED'
      : 'PAGE_PREPARATION_ROUTE_REJECTED',
    routeApproved,
    pageSizeControlFound: false,
    pageSize100Requested: false,
    pageSizeApplyControlFound: false,
    pageSizeApplyTriggered: false,
    pageSizeAlreadyApplied: false,
    headerCheckboxFound: false,
    headerCheckboxSelected: false,
    resultTableStable: false,
    exportRoleMapBuilt: false,
    exportCheckboxFound: false,
    exportCheckboxRoleAmbiguous: false,
    exportCheckboxSelected: false,
    visibleExportRowCount: 0,
    checkedExportRowCount: 0,
    exportButtonFound: false,
    exportButtonEnabled: false,
  };
  const finish = (code) => {
    report.code = code;
    return JSON.stringify(report);
  };
  if (!routeApproved) return JSON.stringify(report);

  const pageSize = Array.from(document.querySelectorAll('select'))
    .find((element) => {
      if (!rendered(element) || element.disabled) return false;
      const labels = Array.from(element.options || [])
        .map((option) => normalize(option.textContent || option.value));
      return ['10', '20', '50', '100']
        .every((value) => labels.includes(value));
    });
  if (!pageSize) return finish('PAGE_SIZE_CONTROL_NOT_FOUND');
  report.pageSizeControlFound = true;

  const option100 = Array.from(pageSize.options || [])
    .find((option) =>
      normalize(option.textContent || option.value) === '100'
    );
  if (!option100) return finish('PAGE_SIZE_100_OPTION_NOT_FOUND');

  const table = Array.from(document.querySelectorAll('table,[role="table"]'))
    .find((element) => {
      const text = normalize(element.textContent);
      return text.includes('發票號碼') && text.includes('發票日期');
    }) || null;
  const rows = table
    ? (() => {
        const bodyRows = Array.from(table.querySelectorAll('tbody tr'))
          .filter(rendered);
        return bodyRows.length > 0
          ? bodyRows
          : Array.from(table.querySelectorAll('[role="row"]'))
              .filter((row) =>
                rendered(row) &&
                !row.closest('thead') &&
                !row.querySelector('[role="columnheader"]')
              );
      })()
    : [];

  const was100 = pageSize.value === option100.value;
  pageSize.value = option100.value;
  pageSize.dispatchEvent(new Event('input', { bubbles: true }));
  pageSize.dispatchEvent(new Event('change', { bubbles: true }));
  report.pageSize100Requested = true;

  const applyIssuedAt = Number(window[applyStateKey] || 0);
  const applyPending =
    was100 &&
    rows.length <= 10 &&
    applyIssuedAt > 0 &&
    Date.now() - applyIssuedAt < 10000;
  if (applyPending) return finish('RESULT_TABLE_RELOADING');

  report.pageSizeAlreadyApplied =
    was100 && (rows.length > 10 || applyIssuedAt === 0);
  if (!report.pageSizeAlreadyApplied) {
    const pageRect = pageSize.getBoundingClientRect();
    const pageCenterY = pageRect.top + pageRect.height / 2;
    const candidates = Array.from(document.querySelectorAll(
      'button,input[type="button"],input[type="submit"],a,[role="button"]'
    )).filter((element) => rendered(element) && !element.disabled)
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return {
          element,
          dx: rect.left - pageRect.right,
          dy: Math.abs(rect.top + rect.height / 2 - pageCenterY),
        };
      }).filter((candidate) =>
        candidate.dx >= -8 &&
        candidate.dx <= 180 &&
        candidate.dy <= Math.max(36, pageRect.height)
      ).sort((left, right) =>
        (Math.abs(left.dx) + left.dy * 2) -
        (Math.abs(right.dx) + right.dy * 2)
      );
    if (candidates.length === 0) {
      return finish('PAGE_SIZE_APPLY_CONTROL_NOT_FOUND');
    }
    report.pageSizeApplyControlFound = true;
    report.pageSizeApplyTriggered = true;
    window[applyStateKey] = Date.now();
    window.setTimeout(() => candidates[0].element.click(), 0);
    return finish('PAGE_SIZE_APPLY_TRIGGERED');
  }

  if (!table || rows.length === 0) return finish('RESULT_TABLE_RELOADING');
  const now = Date.now();
  const previous = window[stableStateKey];
  const stable = previous && typeof previous === 'object'
    ? previous
    : { rowCount: -1, stableSince: now };
  if (stable.rowCount !== rows.length) {
    stable.rowCount = rows.length;
    stable.stableSince = now;
  }
  window[stableStateKey] = stable;
  if (document.readyState !== 'complete' ||
      now - stable.stableSince < stableWindowMs) {
    return finish('RESULT_TABLE_RELOADING');
  }
  report.resultTableStable = true;
  if (!prepareExportSelection) {
    return finish('DETAIL_PAGE_SIZE_READY');
  }

  const rowEntries = [];
  let rowsWithCheckboxes = 0;
  rows.forEach((row, rowIndex) => {
    const boxes = unique(Array.from(row.querySelectorAll(
      'input[type="checkbox"],[role="checkbox"]'
    ))).filter(rendered);
    if (boxes.length === 0) return;
    rowsWithCheckboxes += 1;
    boxes.forEach((element) => {
      const rect = element.getBoundingClientRect();
      rowEntries.push({
        element,
        rowIndex,
        x: rect.left + rect.width / 2,
      });
    });
  });
  if (rowEntries.length === 0) {
    return finish('CSV_EXPORT_CHECKBOX_NOT_FOUND');
  }
  report.exportCheckboxFound = true;

  const clusters = [];
  rowEntries.sort((left, right) => left.x - right.x);
  rowEntries.forEach((entry) => {
    let cluster = clusters.find((candidate) =>
      Math.abs(candidate.x - entry.x) <= clusterTolerance
    );
    if (!cluster) {
      cluster = { x: entry.x, entries: [], rows: new Set() };
      clusters.push(cluster);
    }
    cluster.entries.push(entry);
    cluster.rows.add(entry.rowIndex);
    cluster.x = cluster.entries.reduce(
      (sum, candidate) => sum + candidate.x,
      0
    ) / cluster.entries.length;
  });

  const coverage = Math.max(1, Math.ceil(rowsWithCheckboxes * 0.8));
  const consistentClusters = clusters
    .filter((cluster) => cluster.rows.size >= coverage)
    .sort((left, right) => left.x - right.x);
  report.exportRoleMapBuilt = true;
  if (consistentClusters.length < 2) {
    report.exportCheckboxRoleAmbiguous = true;
    return finish('CSV_EXPORT_CHECKBOX_ROLE_AMBIGUOUS');
  }

  const exportCluster = consistentClusters[consistentClusters.length - 1];
  const leftCluster = consistentClusters[consistentClusters.length - 2];
  if (exportCluster.x - leftCluster.x <= clusterTolerance) {
    report.exportCheckboxRoleAmbiguous = true;
    return finish('CSV_EXPORT_CHECKBOX_ROLE_AMBIGUOUS');
  }

  const exportEntries = Array.from(exportCluster.rows)
    .map((rowIndex) => exportCluster.entries
      .filter((entry) => entry.rowIndex === rowIndex)
      .sort((left, right) =>
        Math.abs(left.x - exportCluster.x) -
        Math.abs(right.x - exportCluster.x)
      )[0])
    .filter((entry) => entry);
  report.visibleExportRowCount = exportEntries.length;
  if (exportEntries.length === 0) {
    return finish('CSV_EXPORT_CHECKBOX_NOT_FOUND');
  }

  const headerBoxes = unique([
    ...Array.from(table.querySelectorAll(
      'thead input[type="checkbox"],thead [role="checkbox"]'
    )),
    ...Array.from(table.querySelectorAll(
      '[role="columnheader"] input[type="checkbox"],' +
      '[role="columnheader"] [role="checkbox"]'
    )),
  ]).filter((element) => {
    if (!rendered(element)) return false;
    const rect = element.getBoundingClientRect();
    return Math.abs(
      rect.left + rect.width / 2 - exportCluster.x
    ) <= headerTolerance;
  });
  if (headerBoxes.length > 1) {
    report.exportCheckboxRoleAmbiguous = true;
    return finish('CSV_EXPORT_CHECKBOX_ROLE_AMBIGUOUS');
  }

  const headerBox = headerBoxes.length === 1 ? headerBoxes[0] : null;
  report.headerCheckboxFound = headerBox !== null;
  if (headerBox && !checked(headerBox)) headerBox.click();
  if (!headerBox) {
    exportEntries.forEach((entry) => {
      if (!checked(entry.element)) entry.element.click();
    });
  }

  const checkedCount = exportEntries
    .filter((entry) => checked(entry.element))
    .length;
  report.checkedExportRowCount = checkedCount;
  report.exportCheckboxSelected = checkedCount === exportEntries.length;
  report.headerCheckboxSelected = headerBox !== null && checked(headerBox);
  if (!report.exportCheckboxSelected) {
    return finish('CSV_EXPORT_SELECTION_INCOMPLETE');
  }

  const exportButtons = Array.from(document.querySelectorAll(
    'button,input[type="button"],input[type="submit"],a,[role="button"]'
  )).filter(rendered).filter((element) => {
    const label = normalize(
      element.textContent ||
      element.value ||
      element.getAttribute('aria-label') ||
      element.getAttribute('title')
    ).toUpperCase();
    return label.includes('下載CSV檔') ||
      (label.includes('下載') && label.includes('CSV'));
  });
  if (exportButtons.length !== 1) {
    return finish(exportButtons.length === 0
      ? 'CSV_EXPORT_BUTTON_NOT_FOUND'
      : 'CSV_EXPORT_BUTTON_ROLE_AMBIGUOUS');
  }

  const exportButton = exportButtons[0];
  report.exportButtonFound = true;
  const style = window.getComputedStyle(exportButton);
  const disabledClass = Array.from(exportButton.classList || [])
    .map((value) => String(value).toLowerCase())
    .some((value) =>
      value === 'disabled' ||
      value === 'is-disabled' ||
      value === 'ui-state-disabled' ||
      value === 'btn-disabled'
    );
  const disabledProperty = exportButton.disabled === true ||
    (typeof exportButton.matches === 'function' &&
     exportButton.matches(':disabled'));
  const ariaDisabled =
    exportButton.getAttribute('aria-disabled') === 'true';
  const pointerEventsDisabled = style.pointerEvents === 'none';
  const rect = exportButton.getBoundingClientRect();
  const centerX = rect.left + rect.width / 2;
  const centerY = rect.top + rect.height / 2;
  const inViewport =
    centerX >= 0 && centerY >= 0 &&
    centerX <= window.innerWidth && centerY <= window.innerHeight;
  const hitTarget = inViewport
    ? document.elementFromPoint(centerX, centerY)
    : exportButton;
  const pointerReady = hitTarget !== null &&
    (hitTarget === exportButton ||
     exportButton.contains(hitTarget) ||
     hitTarget.contains(exportButton));

  report.exportButtonEnabled =
    !disabledProperty &&
    !ariaDisabled &&
    !disabledClass &&
    !pointerEventsDisabled &&
    pointerReady;
  return finish(report.exportButtonEnabled
    ? 'CSV_EXPORT_READY'
    : 'CSV_EXPORT_BUTTON_STILL_DISABLED');
})()
''';
}

String buildOfficialQueryPageFinalizePreparationScript() =>
    buildOfficialQueryPagePreparationScript();
