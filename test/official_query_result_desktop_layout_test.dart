import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_query_result_desktop_layout.dart';
import 'package:my_finance_app/features/invoice/lab/official_query_result_selector_probe.dart';

void main() {
  test('result layout applies a bounded desktop viewport profile', () {
    final script = buildOfficialQueryResultDesktopLayoutScript();

    expect(script, contains('desktopViewportWidth = 1280'));
    expect(script, contains('desktopMinimumContentWidth = 1180'));
    expect(script, contains('meta[name="viewport"]'));
    expect(script, contains("'width=' + desktopViewportWidth"));
    expect(script, contains('DESKTOP_VIEWPORT_READY'));
    expect(script, contains('DESKTOP_VIEWPORT_NOT_READY'));
    expect(script, contains('__privateLabDesktopProfileBadge'));
    expect(script, contains('LAB 桌面設定：'));
    expect(script, contains('視窗 '));
    expect(script, contains('表頭 '));
    expect(script, contains('MutationObserver'));
    expect(script, contains('mutationIsLabBadgeOnly'));
    expect(script, contains('mutations.every(mutationIsLabBadgeOnly)'));
    expect(script, contains('badge.textContent !== nextText'));
    expect(script, contains('setImportantIfChanged'));
    expect(script, contains('requestOneResize'));
    expect(script, contains('__privateLabDesktopViewportResizePending'));
    expect(script, contains('scheduleRefresh'));
    expect(script, contains('window.setTimeout(stopObserver, 300000)'));
    expect(script, contains('removeLabProperty'));
    expect(script, contains("removeLabProperty(cell, 'display'"));
    expect(script, contains("removeLabProperty(cell, 'visibility'"));
    expect(script, contains("removeLabProperty(cell, 'max-width'"));
    expect(script, isNot(contains('canonicalColumnIndexes')));
    expect(script, isNot(contains('setCellVisible')));
    expect(
      script,
      isNot(contains("setProperty('display', 'table-cell', 'important')")),
    );
    expect(
      script,
      isNot(contains("setProperty('display', 'none', 'important')")),
    );
    expect(script, isNot(contains('innerHTML')));
    expect(script, isNot(contains('outerHTML')));
    expect(script, isNot(contains('fetch(')));
    expect(script, isNot(contains('XMLHttpRequest')));
  });

  test('complete result probe requires full columns and CSV selection controls', () {
    final script = buildOfficialQueryResultSelectorProbeScript();

    expect(script, contains('completeResultHeaders'));
    expect(script, contains('捐贈日期'));
    expect(script, contains('買方統編'));
    expect(script, contains('rowSelectionCount > 0'));
    expect(script, contains('headerSelectionCount > 0'));
    expect(script, contains('csvDownloadCount > 0'));
    expect(script, contains('下載CSV檔'));
    expect(script, contains('getBoundingClientRect'));
    expect(script, isNot(contains('innerHTML')));
    expect(script, isNot(contains('outerHTML')));
    expect(script, isNot(contains('fetch(')));
    expect(script, isNot(contains('XMLHttpRequest')));
  });
}
