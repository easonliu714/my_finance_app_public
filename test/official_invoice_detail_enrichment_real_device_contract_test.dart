import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_script.dart';

void main() {
  group('official invoice detail real-device contract', () {
    test('uses rendered summary-table mapping and accepts the 金額 header', () {
      final script = buildOfficialInvoiceDetailEnrichmentScript(
        scope: OfficialInvoiceDetailSelectionScope.selectedInvoices,
        handlerName: 'test-handler',
      );

      expect(script, contains('const extractSummary = (table) =>'));
      expect(script, contains('const summary = extractSummary(summaryTable);'));
      expect(
        script,
        contains("value(['金額', '發票金額', '總計', '總金額'])"),
      );
      expect(
        script,
        contains("['發票日期', '開立時間', '交易時間']"),
      );
      expect(
        script,
        contains("['賣方統一編號', '賣方統編']"),
      );
    });

    test('supports Bootstrap dialog lifecycle and waits for item rows', () {
      final script = buildOfficialInvoiceDetailEnrichmentScript(
        scope: OfficialInvoiceDetailSelectionScope.singleInvoice,
        handlerName: 'test-handler',
        singleInvoiceNumber: 'AN90000009',
      );

      expect(script, contains('.modal.in'));
      expect(script, contains('waitForDialogReady'));
      expect(script, contains('itemRows.length === 0'));
      expect(script, contains('DETAIL_ITEM_TABLE_NOT_FOUND'));
      expect(script, contains('DETAIL_RENDER_TIMEOUT'));
    });

    test('supports Chinese year month day timestamp text', () {
      final script = buildOfficialInvoiceDetailEnrichmentScript(
        scope: OfficialInvoiceDetailSelectionScope.singleInvoice,
        handlerName: 'test-handler',
        singleInvoiceNumber: 'AN90000009',
      );

      expect(script, contains(r'[年\/-]'));
      expect(script, contains(r'[月\/-]'));
      expect(script, contains('日?'));
    });

    test('does not reject otherwise valid detail when currency is absent', () {
      final script = buildOfficialInvoiceDetailEnrichmentScript(
        scope: OfficialInvoiceDetailSelectionScope.currentPage,
        handlerName: 'test-handler',
      );

      expect(script, isNot(contains('base.currencyCode !== null')));
      expect(script, contains('base.exactTimestamp !== null &&'));
      expect(script, contains('base.lineItems.length > 0;'));
    });

    test('model keeps missing currency provenance without blocking time/items', () {
      final result = OfficialInvoiceDetailEnrichment.fromJson(
        <String, Object?>{
          'requestedInvoiceNumber': 'AN90000009',
          'invoiceNumber': 'AN90000009',
          'selectorProfileVersion': officialInvoiceDetailSelectorProfileVersion,
          'fetchedAt': '2026-06-24T01:00:00Z',
          'success': true,
          'invoiceIdentityMatches': true,
          'detailTotalInternallyConsistent': true,
          'detailTotalMatchesCsv': true,
          'sellerIdentifierConsistent': true,
          'lineItems': <Object?>[
            <String, Object?>{
              'name': '測試品項',
              'quantity': 1,
              'unitPrice': 47,
              'amount': 47,
            },
          ],
          'exactTimestamp': '2026-06-24T08:05:03',
          'currencyCode': null,
          'expectedTotal': 47,
          'detailTotal': 47,
          'dialogDetected': true,
          'summaryTableDetected': true,
          'itemTableDetected': true,
          'detectedItemRowCount': 1,
        },
      );

      expect(result.success, isTrue);
      expect(result.canUpgradeTime, isTrue);
      expect(result.canUseOfficialLineItems, isTrue);
      expect(result.canUpgradeCurrency, isFalse);
      expect(result.currencyCode, isNull);
    });
  });
}
