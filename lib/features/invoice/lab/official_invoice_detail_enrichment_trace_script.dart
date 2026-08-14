import 'official_invoice_detail_enrichment.dart';
import 'official_invoice_detail_enrichment_script.dart';

String buildOfficialInvoiceDetailEnrichmentTraceScript({
  required OfficialInvoiceDetailSelectionScope scope,
  required String handlerName,
  String? singleInvoiceNumber,
}) {
  var source = buildOfficialInvoiceDetailEnrichmentScript(
    scope: scope,
    handlerName: handlerName,
    singleInvoiceNumber: singleInvoiceNumber,
  );

  const dialogReadyMarker =
      '  const waitForDialogReady = async (invoiceNumber) => waitFor(() => {';
  const dialogPreparation = r'''  const expectedItemCountOf = (dialog) => {
    const text = String(dialog.textContent || '').replace(/\s+/g, '');
    const patterns = [
      /(?:共|合計|總計)(\d{1,4})筆/g,
      /(\d{1,4})筆(?:資料|項目)/g
    ];
    for (const pattern of patterns) {
      for (const match of text.matchAll(pattern)) {
        const value = Number(match[1]);
        if (Number.isInteger(value) && value > 0) return value;
      }
    }
    return null;
  };
  const nativePageSizeSelect = (dialog) => Array.from(
    dialog.querySelectorAll('select')
  ).filter(rendered).find((select) => Array.from(select.options || []).some(
    (option) => normalize(option.textContent || option.value) === '100'
  )) || null;
  const selectedPageSize100 = (select) => {
    if (!select) return false;
    const selectedText = select.selectedIndex >= 0
      ? normalize(select.options[select.selectedIndex].textContent)
      : '';
    return selectedText === '100' || normalize(select.value) === '100';
  };
  const pageSizeApplyControl = (anchor) => {
    if (!anchor) return null;
    const selector = [
      'button',
      'a',
      '[role="button"]',
      'input[type="button"]',
      'input[type="submit"]'
    ].join(',');
    const directSibling = anchor.nextElementSibling;
    const direct = directSibling && (
      directSibling.matches(selector)
        ? directSibling
        : directSibling.querySelector(selector)
    );
    if (direct && rendered(direct) && !direct.disabled) return direct;

    const anchorRect = anchor.getBoundingClientRect();
    const roots = [
      anchor.parentElement,
      anchor.closest('form'),
      anchor.closest('.form-inline'),
      anchor.closest('.dataTables_length'),
      anchor.closest('[class*="page"]')
    ].filter((root, index, values) =>
      root && values.indexOf(root) === index
    );
    let best = null;
    for (const root of roots) {
      for (const element of Array.from(root.querySelectorAll(selector))) {
        if (!rendered(element) || element.disabled || element === anchor) continue;
        const rect = element.getBoundingClientRect();
        const verticalDistance = Math.abs(
          (rect.top + rect.height / 2) -
          (anchorRect.top + anchorRect.height / 2)
        );
        const horizontalGap = rect.left - anchorRect.right;
        const text = normalize(
          element.textContent ||
          element.value ||
          element.getAttribute('aria-label') ||
          element.getAttribute('title')
        ).toLowerCase();
        const classes = String(element.className || '').toLowerCase();
        let score = 0;
        if (horizontalGap >= -8 && horizontalGap <= 120 &&
            verticalDistance <= 40) score += 120;
        if (root === anchor.parentElement) score += 20;
        if (/查詢|更新|套用|送出|確定|執行|apply|submit|go/.test(text)) {
          score += 45;
        }
        if (/arrow-right|circle-arrow-right|refresh|search|play|check/.test(
          classes
        )) score += 35;
        if (!best || score > best.score) best = { element, score };
      }
    }
    return best && best.score > 0 ? best.element : null;
  };
  const triggerPageSizeApply = (anchor) => {
    const control = pageSizeApplyControl(anchor);
    if (!control) {
      return {
        pageSizeApplyControlDetected: false,
        pageSizeApplyTriggered: false
      };
    }
    try {
      control.click();
      return {
        pageSizeApplyControlDetected: true,
        pageSizeApplyTriggered: true
      };
    } catch (_) {
      return {
        pageSizeApplyControlDetected: true,
        pageSizeApplyTriggered: false
      };
    }
  };
  const dispatchNativePageSize100 = (select, option) => {
    try {
      const descriptor = Object.getOwnPropertyDescriptor(
        window.HTMLSelectElement.prototype,
        'value'
      );
      if (descriptor && descriptor.set) {
        descriptor.set.call(select, option.value);
      } else {
        select.value = option.value;
      }
      Array.from(select.options || []).forEach((candidate) => {
        candidate.selected = candidate === option;
      });
      select.dispatchEvent(new Event('input', {
        bubbles: true,
        composed: true
      }));
      select.dispatchEvent(new Event('change', {
        bubbles: true,
        composed: true
      }));
      if (window.jQuery) {
        try {
          window.jQuery(select).val(option.value).trigger('change');
        } catch (_) {}
      }
    } catch (_) {}
  };
  const requestPageSize100 = async (dialog) => {
    const attempt = {
      pageSizeControlDetected: false,
      pageSize100OptionDetected: false,
      pageSize100SelectionObserved: false,
      pageSizeApplyControlDetected: false,
      pageSizeApplyTriggered: false,
      pageSizeSelectionStrategy: 'none'
    };
    const select = nativePageSizeSelect(dialog);
    if (select) {
      attempt.pageSizeControlDetected = true;
      attempt.pageSizeSelectionStrategy = 'native-select';
      const option = Array.from(select.options || []).find(
        (candidate) =>
          normalize(candidate.textContent || candidate.value) === '100'
      );
      if (!option) return attempt;
      attempt.pageSize100OptionDetected = true;
      if (!selectedPageSize100(select)) {
        dispatchNativePageSize100(select, option);
        await sleep(350);
      }
      if (!selectedPageSize100(select)) {
        try { option.click(); } catch (_) {}
        dispatchNativePageSize100(select, option);
        await sleep(350);
      }
      attempt.pageSize100SelectionObserved = selectedPageSize100(select);
      Object.assign(attempt, triggerPageSizeApply(select));
      await sleep(attempt.pageSizeApplyTriggered ? 700 : 350);
      return attempt;
    }

    const triggers = Array.from(dialog.querySelectorAll(
      '[role="combobox"],button,[role="button"]'
    )).filter((element) => {
      if (!rendered(element)) return false;
      const text = normalize(
        element.textContent ||
        element.getAttribute('aria-label') ||
        element.getAttribute('title')
      );
      return text.includes('顯示') || text.includes('每頁') ||
        element.getAttribute('role') === 'combobox';
    });
    for (const trigger of triggers) {
      attempt.pageSizeControlDetected = true;
      attempt.pageSizeSelectionStrategy = 'custom-control';
      trigger.click();
      await sleep(220);
      const options = Array.from(document.querySelectorAll(
        '[role="option"],.dropdown-menu li,.select2-results__option,.p-dropdown-item'
      )).filter((element) =>
        rendered(element) && normalize(element.textContent) === '100'
      );
      if (options.length > 0) {
        attempt.pageSize100OptionDetected = true;
        options[0].click();
        await sleep(350);
        const triggerText = normalize(
          trigger.textContent || trigger.getAttribute('aria-label') || ''
        );
        attempt.pageSize100SelectionObserved =
          triggerText.includes('100') ||
          options[0].getAttribute('aria-selected') === 'true';
        Object.assign(attempt, triggerPageSizeApply(trigger));
        await sleep(attempt.pageSizeApplyTriggered ? 700 : 350);
        return attempt;
      }
    }
    return attempt;
  };
  const preparedItemTableOf = (dialog) => {
    const candidates = Array.from(
      dialog.querySelectorAll('table,[role="table"],[role="grid"]')
    ).filter(rendered).filter((candidate) => {
      const profileData = tableProfile(candidate);
      return indexOfHeader(profileData.headers, ['品名', '商品名稱']) >= 0 &&
        indexOfHeader(profileData.headers, ['金額', '小計']) >= 0;
    });
    candidates.sort((left, right) =>
      tableProfile(right).rows.length - tableProfile(left).rows.length
    );
    return candidates[0] || findItemTable(dialog);
  };
  const preparedItemState = ({
    dialog,
    summaryTable,
    itemTable,
    expectedItemCount
  }) => {
    const itemListTruncated = expectedItemCount > 100;
    return {
      dialog,
      summaryTable,
      itemTable,
      expectedItemCount,
      readableItemLimit: itemListTruncated ? 100 : expectedItemCount,
      itemListTruncated,
      warningCode: itemListTruncated
        ? 'DETAIL_ITEM_LIST_TRUNCATED_TO_100'
        : null,
      errorCode: null
    };
  };
  const prepareOfficialDetailItems = async (invoiceNumber) => {
    const initial = await waitForDialogReady(invoiceNumber);
    if (!initial) return null;
    const expected = expectedItemCountOf(initial.dialog);
    const initialRows = tableProfile(initial.itemTable).rows.length;
    if (expected === null) {
      return {
        ...initial,
        expectedItemCount: null,
        errorCode: 'DETAIL_ITEM_TOTAL_NOT_FOUND'
      };
    }
    const requiredVisibleCount = Math.min(expected, 100);
    if (initialRows >= requiredVisibleCount) {
      if (expected <= 100 && initialRows !== expected) {
        return {
          ...initial,
          expectedItemCount: expected,
          errorCode: 'DETAIL_ITEM_COUNT_MISMATCH'
        };
      }
      return preparedItemState({
        ...initial,
        expectedItemCount: expected
      });
    }

    const pageSizeAttempt = await requestPageSize100(initial.dialog);
    if (!pageSizeAttempt.pageSize100OptionDetected) {
      return {
        ...initial,
        expectedItemCount: expected,
        initialItemRowCount: initialRows,
        requiredVisibleItemCount: requiredVisibleCount,
        ...pageSizeAttempt,
        errorCode: 'DETAIL_ITEM_PAGE_SIZE_100_NOT_AVAILABLE'
      };
    }

    let previousCount = -1;
    let stablePasses = 0;
    let maxObservedItemRowCount = initialRows;
    let loadingMaskObserved = false;
    let latestDialog = initial.dialog;
    let latestSummaryTable = initial.summaryTable;
    let latestItemTable = initial.itemTable;
    let reapplied = false;
    const reloadStartedAt = Date.now();
    const prepared = await waitFor(() => {
      const dialog = findDetailDialog(invoiceNumber);
      if (!dialog) return null;
      latestDialog = dialog;
      if (hasLoadingMask(dialog)) {
        loadingMaskObserved = true;
        return null;
      }
      const summaryTable = findSummaryTable(dialog);
      const itemTable = preparedItemTableOf(dialog);
      if (!summaryTable || !itemTable) return null;
      latestSummaryTable = summaryTable;
      latestItemTable = itemTable;
      const currentExpected = expectedItemCountOf(dialog);
      const count = tableProfile(itemTable).rows.length;
      maxObservedItemRowCount = Math.max(maxObservedItemRowCount, count);
      stablePasses = count === previousCount ? stablePasses + 1 : 0;
      previousCount = count;
      if (!reapplied &&
          Date.now() - reloadStartedAt >= 7000 &&
          count < requiredVisibleCount) {
        reapplied = true;
        void requestPageSize100(dialog);
      }
      if (currentExpected === expected &&
          count >= requiredVisibleCount &&
          stablePasses >= 2) {
        if (expected <= 100 && count !== expected) {
          return {
            dialog,
            summaryTable,
            itemTable,
            expectedItemCount: expected,
            initialItemRowCount: initialRows,
            requiredVisibleItemCount: requiredVisibleCount,
            detectedItemRowCount: count,
            loadingMaskObserved,
            ...pageSizeAttempt,
            errorCode: 'DETAIL_ITEM_COUNT_MISMATCH'
          };
        }
        return {
          ...preparedItemState({
            dialog,
            summaryTable,
            itemTable,
            expectedItemCount: expected
          }),
          initialItemRowCount: initialRows,
          requiredVisibleItemCount: requiredVisibleCount,
          detectedItemRowCount: count,
          loadingMaskObserved,
          ...pageSizeAttempt
        };
      }
      return null;
    }, 30000);
    return prepared || {
      dialog: latestDialog,
      summaryTable: latestSummaryTable,
      itemTable: latestItemTable,
      expectedItemCount: expected,
      initialItemRowCount: initialRows,
      requiredVisibleItemCount: requiredVisibleCount,
      detectedItemRowCount: maxObservedItemRowCount,
      loadingMaskObserved,
      ...pageSizeAttempt,
      errorCode: pageSizeAttempt.pageSizeApplyTriggered
        ? 'DETAIL_ITEM_TABLE_RELOAD_TIMEOUT'
        : 'DETAIL_ITEM_PAGE_SIZE_APPLY_NOT_TRIGGERED'
    };
  };
  const waitForDialogReady = async (invoiceNumber) => waitFor(() => {''';
  if (!source.contains(dialogReadyMarker)) {
    throw StateError('DETAIL_INNER_PAGE_SIZE_MARKER_NOT_FOUND');
  }
  source = source.replaceFirst(dialogReadyMarker, dialogPreparation);

  const readyCallOriginal =
      '      const ready = await waitForDialogReady(target.invoiceNumber);';
  const readyCallReplacement = r'''      const ready = await prepareOfficialDetailItems(target.invoiceNumber);
      if (ready && ready.errorCode) {
        base.summaryTableDetected = !!ready.summaryTable;
        base.itemTableDetected = !!ready.itemTable;
        base.detectedItemRowCount = Number(
          ready.detectedItemRowCount ||
          (ready.itemTable ? tableProfile(ready.itemTable).rows.length : 0)
        );
        base.initialItemRowCount = Number(ready.initialItemRowCount || 0);
        base.requiredVisibleItemCount = Number(
          ready.requiredVisibleItemCount || 0
        );
        base.pageSizeControlDetected =
          ready.pageSizeControlDetected === true;
        base.pageSize100OptionDetected =
          ready.pageSize100OptionDetected === true;
        base.pageSize100SelectionObserved =
          ready.pageSize100SelectionObserved === true;
        base.pageSizeApplyControlDetected =
          ready.pageSizeApplyControlDetected === true;
        base.pageSizeApplyTriggered = ready.pageSizeApplyTriggered === true;
        base.loadingMaskObserved = ready.loadingMaskObserved === true;
        base.errorCode = ready.errorCode;
        send({ type: 'result', result: base });
        await closeDialog(ready.dialog || firstDialog);
        continue;
      }''';
  if (!source.contains(readyCallOriginal)) {
    throw StateError('DETAIL_PREPARE_CALL_MARKER_NOT_FOUND');
  }
  source = source.replaceFirst(readyCallOriginal, readyCallReplacement);

  const itemExtractOriginal =
      '      const productItems = extractLineItems(itemTable);';
  const itemExtractReplacement = r'''      const expectedItemCount = Number(ready.expectedItemCount || 0);
      const readableItemLimit = Number(
        ready.readableItemLimit || expectedItemCount
      );
      const extractedItems = extractLineItems(itemTable);
      const productItems = extractedItems.slice(0, readableItemLimit);
      const requiredReadableCount = ready.itemListTruncated
        ? 100
        : expectedItemCount;
      base.declaredItemCount = expectedItemCount;
      base.lineItemsTruncated = ready.itemListTruncated === true;
      base.omittedItemCount = Math.max(
        0,
        expectedItemCount - productItems.length
      );
      base.warningCode = ready.warningCode || null;
      if (requiredReadableCount <= 0 ||
          productItems.length !== requiredReadableCount) {
        base.detectedItemRowCount = productItems.length;
        base.errorCode = 'DETAIL_ITEM_COUNT_MISMATCH';
        send({ type: 'result', result: base });
        await closeDialog(dialog);
        await sleep(650);
        continue;
      }''';
  if (!source.contains(itemExtractOriginal)) {
    throw StateError('DETAIL_ITEM_EXTRACT_MARKER_NOT_FOUND');
  }
  source = source.replaceFirst(itemExtractOriginal, itemExtractReplacement);

  const finalResultOriginal = '''      send({ type: 'result', result: base });
      await closeDialog(dialog);''';
  const finalResultReplacement = r'''      if (base.lineItemsTruncated &&
          base.invoiceIdentityMatches &&
          base.detailTotalMatchesCsv &&
          base.exactTimestamp !== null &&
          base.lineItems.length > 0) {
        base.success = true;
        base.errorCode = null;
      }
      send({ type: 'result', result: base });
      await closeDialog(dialog);''';
  if (!source.contains(finalResultOriginal)) {
    throw StateError('DETAIL_TRUNCATED_SUCCESS_MARKER_NOT_FOUND');
  }
  source = source.replaceFirst(finalResultOriginal, finalResultReplacement);

  const startedOriginal =
      "send({ type: 'started', total: targets.length });";
  const startedReplacement = '''send({
    type: 'started',
    total: targets.length,
    targets: targets.map((target, index) => ({
      invoiceNumber: target.invoiceNumber,
      ordinal: index + 1
    }))
  });''';
  if (!source.contains(startedOriginal)) {
    throw StateError('DETAIL_TRACE_START_MARKER_NOT_FOUND');
  }
  source = source.replaceFirst(startedOriginal, startedReplacement);

  const resultOriginal = "send({ type: 'result', result: base });";
  const resultReplacement =
      "send({ type: 'result', ordinal: index + 1, result: base });";
  final resultMarkerCount = resultOriginal.allMatches(source).length;
  if (resultMarkerCount == 0) {
    throw StateError('DETAIL_TRACE_RESULT_MARKER_NOT_FOUND');
  }
  return source.replaceAll(resultOriginal, resultReplacement);
}
