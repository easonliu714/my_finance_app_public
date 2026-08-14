import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 6, 17, 12);
  final adapter = OfficialCloudInvoiceCsvAdapter(clock: () => fixedNow);

  test('groups detail rows and sums positive and negative amounts', () {
    final preview = adapter.createPreview(_sampleCsv());

    expect(preview.detailRowCount, 4);
    expect(preview.invoiceCount, 2);
    expect(preview.supportedInvoiceCount, 2);
    expect(preview.blockedInvoiceCount, 0);
    expect(preview.repairedRowCount, 1);
    expect(preview.ignoredFooterCount, 2);
    expect(preview.earliestInvoiceDate, DateTime(2026, 5, 11));
    expect(preview.latestInvoiceDate, DateTime(2026, 5, 30));
    expect(preview.canCreateFormalTransactionAutomatically, isFalse);

    final local = preview.invoices.singleWhere(
      (invoice) => invoice.candidate!.invoiceNumber == 'AG90000006',
    );
    expect(local.detailRowCount, 3);
    expect(local.candidate!.totalAmount, 99);
    expect(local.candidate!.lineItems, hasLength(3));
    expect(
      local.candidate!.lineItems.map((item) => item.amount),
      containsAll(<double>[79, 29, -9]),
    );
    expect(local.candidate!.rawPayload, isNull);
    expect(
      local.candidate!.source,
      CloudInvoiceCandidateSource.privateCloudResearch,
    );
  });

  test('repairs an unquoted comma in seller name and warns on currency', () {
    final preview = adapter.createPreview(_sampleCsv());
    final foreign = preview.invoices.singleWhere(
      (invoice) => invoice.candidate!.invoiceNumber == 'AD90000003',
    );

    expect(foreign.candidate!.sellerName, 'EXAMPLE AI, INC.');
    expect(foreign.candidate!.totalAmount, 6.64);
    expect(
      foreign.issues.map((issue) => issue.code),
      contains(
        OfficialCloudInvoiceCsvIssueCode.fractionalAmountCurrencyUnknown,
      ),
    );
    expect(
      foreign.candidate!.warnings,
      contains(CloudInvoiceCandidateWarning.lowConfidence),
    );
    expect(
      preview.fileIssues.map((issue) => issue.code),
      contains(OfficialCloudInvoiceCsvIssueCode.repairedSellerNameComma),
    );
  });

  test('supports a correctly quoted comma in seller name', () {
    final csv = '${_header()}\n'
        'Gmail,20260511,AD90000003,6.64,開立已確認,否,00610415,'
        '"EXAMPLE AI, INC.",臺北市中正區,,1,6.64,6.64,服務費';
    final preview = adapter.createPreview(csv);

    expect(preview.repairedRowCount, 0);
    expect(preview.supportedInvoiceCount, 1);
    expect(
      preview.invoices.single.candidate!.sellerName,
      'EXAMPLE AI, INC.',
    );
  });

  test('ignores known official footer lines only', () {
    final preview = adapter.createPreview(_sampleCsv());

    expect(preview.ignoredFooterCount, 2);
    expect(preview.fileIssues.where((issue) => issue.isBlocking), isEmpty);
  });

  test('blocks malformed rows and prevents all import', () {
    final csv = '${_header()}\n'
        '手機條碼,20260531,BM90000013';
    final preview = adapter.createPreview(csv);

    expect(preview.isBlocked, isTrue);
    expect(preview.canImport, isFalse);
    expect(preview.importAllSupported(), isEmpty);
    expect(
      preview.fileIssues.map((issue) => issue.code),
      contains(OfficialCloudInvoiceCsvIssueCode.malformedRow),
    );
  });

  test('blocks invalid headers', () {
    final preview = adapter.createPreview('wrong,header\n1,2');

    expect(preview.isBlocked, isTrue);
    expect(preview.invoiceCount, 0);
    expect(
      preview.fileIssues.single.code,
      OfficialCloudInvoiceCsvIssueCode.invalidHeader,
    );
  });

  test('blocks void or unsupported invoice status', () {
    final csv = '${_header()}\n'
        '手機條碼,20260531,BM90000013,75,作廢,否,87588837,'
        '測試商店,桃園市,,1,75,75,測試商品';
    final preview = adapter.createPreview(csv);

    expect(preview.invoiceCount, 1);
    expect(preview.blockedInvoiceCount, 1);
    expect(preview.invoices.single.candidate, isNull);
    expect(
      preview.invoices.single.issues.map((issue) => issue.code),
      contains(OfficialCloudInvoiceCsvIssueCode.unsupportedInvoiceStatus),
    );
  });

  test('blocks masked invoice numbers from formal candidate creation', () {
    final csv = '${_header()}\n'
        '手機條碼,20260531,BM23888***,75,開立已確認,否,87588837,'
        '測試商店,桃園市,,1,75,75,測試商品';
    final preview = adapter.createPreview(csv);

    expect(preview.blockedInvoiceCount, 1);
    expect(
      preview.invoices.single.issues.map((issue) => issue.code),
      contains(OfficialCloudInvoiceCsvIssueCode.maskedInvoiceNumber),
    );
  });

  test('selected import returns invoice candidates rather than detail rows', () {
    final preview = adapter.createPreview(_sampleCsv());
    final target = preview.invoices.singleWhere(
      (invoice) => invoice.candidate!.invoiceNumber == 'AG90000006',
    );

    final selected = preview.importSelected(<String>{target.id});
    expect(selected, hasLength(1));
    expect(selected.single.invoiceNumber, 'AG90000006');
    expect(selected.single.totalAmount, 99);
    expect(preview.importAllSupported(), hasLength(2));
    expect(preview.cancel(), isEmpty);
  });

  test('reports row amount mismatch without blocking candidate', () {
    final csv = '${_header()}\n'
        '手機條碼,20260531,BM90000013,70,開立已確認,否,87588837,'
        '測試商店,桃園市,,1,75,75,測試商品';
    final preview = adapter.createPreview(csv);

    expect(preview.supportedInvoiceCount, 1);
    expect(
      preview.invoices.single.issues.map((issue) => issue.code),
      contains(OfficialCloudInvoiceCsvIssueCode.rowAmountMismatch),
    );
  });
}

String _header() => officialCloudInvoiceCsvHeaders.join(',');

String _sampleCsv() {
  return '\ufeff${_header()}\n'
      '手機條碼,20260530,AG90000006,79,開立已確認,否,24813702,'
      '便利商店,台北市松山區,,1,79,79,餐點\n'
      '手機條碼,20260530,AG90000006,29,開立已確認,否,24813702,'
      '便利商店,台北市松山區,,1,29,29,飲料\n'
      '手機條碼,20260530,AG90000006,-9,開立已確認,否,24813702,'
      '便利商店,台北市松山區,,1,0,-9,促銷折扣\n'
      'Gmail,20260511,AD90000003,6.64,開立已確認,否,00610415,'
      'EXAMPLE AI, INC.,臺北市中正區,,1,6.64,6.64,服務費\n'
      '捐贈或作廢之發票，字軌號碼均會隱末3碼\n'
      '注意：本功能所下載之雲端發票明細檔案可能因賣方營業人後續作廢或折讓等原因而產生誤差。';
}
