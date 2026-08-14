import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_trace_script.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_retry.dart';

void main() {
  test('inner 100-row preparation triggers the adjacent official apply control', () {
    final script = buildOfficialInvoiceDetailEnrichmentTraceScript(
      scope: OfficialInvoiceDetailSelectionScope.singleInvoice,
      handlerName: 'p4-12-38-handler',
      singleInvoiceNumber: 'BG90000012',
    );

    expect(script, contains('triggerPageSizeApply'));
    expect(script, contains('pageSizeApplyControlDetected'));
    expect(script, contains('pageSizeApplyTriggered'));
    expect(script, contains('preparedItemTableOf'));
    expect(script, contains('DETAIL_ITEM_PAGE_SIZE_APPLY_NOT_TRIGGERED'));
    expect(
      officialInvoiceDetailResidualCategoryForCode(
        'DETAIL_ITEM_PAGE_SIZE_APPLY_NOT_TRIGGERED',
      ),
      OfficialInvoiceDetailResidualCategory.technicalRetryable,
    );
  });

  test('actual account amount fills a two-decimal visible exchange rate', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();

    expect(source, contains('(actual / draft.amount).toStringAsFixed(2)'));
    expect(source, contains('actualAmountFieldRevisionByDraftId'));
    expect(source, contains('自動填入上方欄位至小數點後 2 位'));
  });

  test('dashboard feed omits long transaction notes and stays compact', () {
    final source = File(
      'lib/features/dashboard/dashboard_page.dart',
    ).readAsStringSync();
    final tileStart = source.indexOf('class _TransactionListTile');
    final tileEnd = source.indexOf('class _DayGroup');
    expect(tileStart, greaterThanOrEqualTo(0));
    expect(tileEnd, greaterThan(tileStart));
    final tileSource = source.substring(tileStart, tileEnd);

    expect(tileSource, isNot(contains('record.note')));
    expect(tileSource, contains('maxLines: 2'));
    expect(tileSource, contains('TextOverflow.ellipsis'));
    expect(tileSource, contains("merchant != '不使用商家'"));
  });

  test('new apply-control diagnostics deserialize without raw page data', () {
    final item = OfficialInvoiceDetailEnrichment.fromJson(
      <String, Object?>{
        'requestedInvoiceNumber': 'BG90000012',
        'invoiceNumber': '',
        'selectorProfileVersion': 6,
        'fetchedAt': DateTime.utc(2026, 7, 1).toIso8601String(),
        'success': false,
        'invoiceIdentityMatches': false,
        'detailTotalInternallyConsistent': false,
        'detailTotalMatchesCsv': false,
        'sellerIdentifierConsistent': true,
        'lineItems': const <Object?>[],
        'pageSizeControlDetected': true,
        'pageSize100OptionDetected': true,
        'pageSize100SelectionObserved': true,
        'pageSizeApplyControlDetected': true,
        'pageSizeApplyTriggered': true,
        'errorCode': 'DETAIL_ITEM_TABLE_RELOAD_TIMEOUT',
      },
    );

    expect(item.pageSizeApplyControlDetected, isTrue);
    expect(item.pageSizeApplyTriggered, isTrue);
    expect(officialInvoiceDetailSelectorProfileVersion, 7);
  });
}
