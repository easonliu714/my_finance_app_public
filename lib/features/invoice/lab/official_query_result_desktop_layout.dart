import 'dart:convert';

import 'authenticated_selector_capability_probe.dart';

/// Applies the same effective profile as a mobile browser's "desktop site"
/// option while preserving the official portal's native DOM and controls.
///
/// The official query remains on the user-visible `/mobile/btc502w` route, but
/// the responsive breakpoint is forced to a wide layout before the user runs
/// the query. No invoice values, credentials, DOM, or HTML are read or stored.
String buildOfficialQueryResultDesktopLayoutScript() {
  final encodedOrigin = jsonEncode(approvedCloudInvoiceQueryOrigin);
  final encodedPath = jsonEncode(approvedCloudInvoiceQueryPath);
  final encodedRoutePrefix = jsonEncode('/portal/btc/mobile/btc502w');

  return '''
(() => {
  const approvedOrigin = $encodedOrigin;
  const approvedPath = $encodedPath;
  const approvedRoutePrefix = $encodedRoutePrefix;
  const desktopViewportWidth = 1280;
  const desktopMinimumContentWidth = 1180;
  const requiredHeaders = [
    '載具自訂名稱',
    '發票號碼',
    '發票金額',
    '發票日期',
    '捐贈日期',
    '買方統編',
  ];
  const observerKey = '__privateLabDesktopResultLayoutObserver';
  const observerTimeoutKey = '__privateLabDesktopResultLayoutTimeout';
  const refreshTimeoutKey = '__privateLabDesktopResultLayoutRefresh';
  const resizePendingKey = '__privateLabDesktopViewportResizePending';
  const badgeId = '__privateLabDesktopProfileBadge';
  const normalize = (value) => String(value || '')
    .replace(/[\\s＊*：:]/g, '')
    .trim();
  const routeApproved = () => {
    const path = window.location.pathname;
    return window.location.origin === approvedOrigin &&
      (path === approvedPath ||
       path === approvedRoutePrefix ||
       path.startsWith(approvedRoutePrefix + '/'));
  };
  const findResultTable = () => Array.from(
    document.querySelectorAll('table,[role="table"],[role="grid"]')
  ).find((candidate) => {
    const text = normalize(candidate.textContent);
    return text.includes('發票號碼') && text.includes('發票日期');
  }) || null;

  const removeLabProperty = (element, property, values) => {
    if (!element) return false;
    const priority = element.style.getPropertyPriority(property);
    const value = element.style.getPropertyValue(property).trim();
    if (priority === 'important' && values.includes(value)) {
      element.style.removeProperty(property);
      return true;
    }
    return false;
  };

  const setImportantIfChanged = (element, property, value) => {
    if (!element) return false;
    const currentValue = element.style.getPropertyValue(property).trim();
    const currentPriority = element.style.getPropertyPriority(property);
    if (currentValue === value && currentPriority === 'important') {
      return false;
    }
    element.style.setProperty(property, value, 'important');
    return true;
  };

  const requestOneResize = () => {
    if (window[resizePendingKey]) return;
    window[resizePendingKey] = true;
    window.setTimeout(() => {
      try {
        window.dispatchEvent(new Event('resize'));
      } catch (_) {
        // Responsive CSS still observes the viewport and min-width changes.
      } finally {
        window[resizePendingKey] = false;
      }
    }, 0);
  };

  const ensureDesktopViewport = () => {
    if (!routeApproved() || !document.documentElement) return false;
    let changed = false;
    let viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) {
      viewport = document.createElement('meta');
      viewport.setAttribute('name', 'viewport');
      (document.head || document.documentElement).appendChild(viewport);
      changed = true;
    }
    const viewportContent =
      'width=' + desktopViewportWidth + ', user-scalable=yes';
    if (viewport.getAttribute('content') !== viewportContent) {
      viewport.setAttribute('content', viewportContent);
      changed = true;
    }

    changed = setImportantIfChanged(
      document.documentElement,
      'min-width',
      desktopMinimumContentWidth + 'px',
    ) || changed;
    changed = setImportantIfChanged(
      document.documentElement,
      '-webkit-text-size-adjust',
      '100%',
    ) || changed;
    if (document.body) {
      changed = setImportantIfChanged(
        document.body,
        'min-width',
        desktopMinimumContentWidth + 'px',
      ) || changed;
      if (document.body.getAttribute(
            'data-private-lab-desktop-profile',
          ) !== 'true') {
        document.body.setAttribute(
          'data-private-lab-desktop-profile',
          'true',
        );
        changed = true;
      }
    }
    if (changed) requestOneResize();
    return true;
  };

  const profileSnapshot = () => {
    const table = findResultTable();
    const headers = table
      ? Array.from(table.querySelectorAll('th,[role="columnheader"]'))
          .filter((element) => {
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== 'none' &&
              style.visibility !== 'hidden' &&
              rect.width > 0 && rect.height > 0;
          })
          .map((element) => normalize(element.textContent))
      : [];
    const matchedHeaders = requiredHeaders.filter((header) =>
      headers.some((candidate) => candidate.includes(header))
    ).length;
    const viewportWidth = Math.round(Math.max(
      Number(window.innerWidth || 0),
      Number(document.documentElement?.clientWidth || 0),
    ));
    const userAgent = String(navigator.userAgent || '');
    const desktopUserAgent =
      !/(Android|Mobile|iPhone|iPad|iPod)/i.test(userAgent);
    const userAgentDataMobile =
      navigator.userAgentData &&
      typeof navigator.userAgentData.mobile === 'boolean'
        ? navigator.userAgentData.mobile
        : null;
    const desktopViewportReady = viewportWidth >= 1000;
    return {
      desktopUserAgent,
      userAgentDataMobile,
      viewportWidth,
      matchedHeaders,
      requiredHeaderCount: requiredHeaders.length,
      resultTableFound: table !== null,
      desktopViewportReady,
      desktopResultReady:
        table !== null && matchedHeaders === requiredHeaders.length,
    };
  };

  const updateDiagnosticBadge = () => {
    if (!routeApproved() || !document.body) return;
    const snapshot = profileSnapshot();
    let badge = document.getElementById(badgeId);
    if (!badge) {
      badge = document.createElement('div');
      badge.id = badgeId;
      badge.setAttribute('aria-hidden', 'true');
      badge.style.setProperty('position', 'fixed', 'important');
      badge.style.setProperty('left', '8px', 'important');
      badge.style.setProperty('bottom', '78px', 'important');
      badge.style.setProperty('z-index', '2147483647', 'important');
      badge.style.setProperty('pointer-events', 'none', 'important');
      badge.style.setProperty('padding', '5px 8px', 'important');
      badge.style.setProperty('border-radius', '6px', 'important');
      badge.style.setProperty('font-size', '11px', 'important');
      badge.style.setProperty('line-height', '1.35', 'important');
      badge.style.setProperty('font-family', 'sans-serif', 'important');
      badge.style.setProperty('color', '#ffffff', 'important');
      badge.style.setProperty(
        'background',
        'rgba(24, 48, 82, 0.88)',
        'important',
      );
      document.body.appendChild(badge);
    }
    const ready = snapshot.desktopViewportReady && snapshot.desktopUserAgent;
    const state = ready ? '就緒' : '未就緒';
    const tableState = snapshot.resultTableFound
      ? '｜表頭 ' + snapshot.matchedHeaders + '/' +
        snapshot.requiredHeaderCount
      : '｜尚未查詢';
    const nextText =
      'LAB 桌面設定：' + state +
      '｜視窗 ' + snapshot.viewportWidth + 'px' +
      tableState;
    if (badge.textContent !== nextText) {
      badge.textContent = nextText;
    }
    const nextReady = ready ? 'true' : 'false';
    if (badge.getAttribute('data-private-lab-desktop-ready') !== nextReady) {
      badge.setAttribute('data-private-lab-desktop-ready', nextReady);
    }
  };

  const restoreNativeResultLayout = () => {
    if (!routeApproved()) return false;
    ensureDesktopViewport();
    const table = findResultTable();
    if (!table) {
      updateDiagnosticBadge();
      return false;
    }

    removeLabProperty(table, 'display', ['table']);
    removeLabProperty(table, 'min-width', ['900px']);
    removeLabProperty(table, 'width', ['max-content']);
    removeLabProperty(table, 'table-layout', ['auto']);

    for (const cell of table.querySelectorAll(
      'th,td,[role="columnheader"],[role="cell"]'
    )) {
      const displayPriority = cell.style.getPropertyPriority('display');
      const displayValue = cell.style.getPropertyValue('display').trim();
      const labDisplay = displayPriority === 'important' &&
        (displayValue === 'table-cell' || displayValue === 'none');
      removeLabProperty(cell, 'display', ['table-cell', 'none']);
      removeLabProperty(cell, 'visibility', ['visible']);
      removeLabProperty(cell, 'max-width', ['none']);
      if (labDisplay && cell.getAttribute('aria-hidden') === 'true') {
        cell.removeAttribute('aria-hidden');
      }
    }

    const wrapper = table.closest(
      '.table-responsive,[class*="result"],[class*="table"]'
    ) || table.parentElement;
    if (wrapper) {
      removeLabProperty(wrapper, 'display', ['block']);
      removeLabProperty(wrapper, 'width', ['100%']);
      removeLabProperty(wrapper, 'max-width', ['100%']);
      setImportantIfChanged(wrapper, 'overflow-x', 'auto');
      setImportantIfChanged(
        wrapper,
        '-webkit-overflow-scrolling',
        'touch',
      );
    }

    if (document.body && document.body.hasAttribute(
          'data-private-lab-wide-result-layout',
        )) {
      document.body.removeAttribute(
        'data-private-lab-wide-result-layout',
      );
    }
    updateDiagnosticBadge();
    return profileSnapshot().desktopResultReady;
  };

  const clearScheduledRefresh = () => {
    if (window[refreshTimeoutKey]) {
      window.clearTimeout(window[refreshTimeoutKey]);
    }
    window[refreshTimeoutKey] = null;
  };

  const scheduleRefresh = (delay = 120) => {
    if (window[refreshTimeoutKey]) return;
    window[refreshTimeoutKey] = window.setTimeout(() => {
      window[refreshTimeoutKey] = null;
      ensureDesktopViewport();
      restoreNativeResultLayout();
      updateDiagnosticBadge();
    }, delay);
  };

  const mutationIsLabBadgeOnly = (mutation) => {
    const badge = document.getElementById(badgeId);
    if (!badge) return false;
    if (mutation.target === badge || badge.contains(mutation.target)) {
      return true;
    }
    const changedNodes = [
      ...Array.from(mutation.addedNodes || []),
      ...Array.from(mutation.removedNodes || []),
    ];
    return changedNodes.length > 0 && changedNodes.every((node) =>
      node === badge ||
      (node.nodeType === 1 && badge.contains(node))
    );
  };

  const stopObserver = () => {
    const current = window[observerKey];
    if (current && typeof current.disconnect === 'function') {
      current.disconnect();
    }
    window[observerKey] = null;
    if (window[observerTimeoutKey]) {
      window.clearTimeout(window[observerTimeoutKey]);
    }
    window[observerTimeoutKey] = null;
    clearScheduledRefresh();
  };

  stopObserver();
  ensureDesktopViewport();
  updateDiagnosticBadge();
  if (routeApproved() && document.documentElement) {
    const observer = new MutationObserver((mutations) => {
      if (mutations.length > 0 && mutations.every(mutationIsLabBadgeOnly)) {
        return;
      }
      scheduleRefresh();
    });
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
    });
    window[observerKey] = observer;
    window[observerTimeoutKey] = window.setTimeout(stopObserver, 300000);
  }
  for (const delay of [0, 250, 750, 1500, 3000, 6000, 12000]) {
    window.setTimeout(() => scheduleRefresh(0), delay);
  }
  const snapshot = profileSnapshot();
  return JSON.stringify({
    code: snapshot.desktopResultReady
      ? 'DESKTOP_RESULT_LAYOUT_READY'
      : snapshot.desktopViewportReady && snapshot.desktopUserAgent
        ? 'DESKTOP_VIEWPORT_READY'
        : 'DESKTOP_VIEWPORT_NOT_READY',
    desktopUserAgent: snapshot.desktopUserAgent,
    userAgentDataMobile: snapshot.userAgentDataMobile,
    viewportWidth: snapshot.viewportWidth,
    matchedHeaders: snapshot.matchedHeaders,
    requiredHeaderCount: snapshot.requiredHeaderCount,
    resultTableFound: snapshot.resultTableFound,
  });
})()
''';
}
