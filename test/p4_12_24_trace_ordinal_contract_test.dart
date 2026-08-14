import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_trace_script.dart';

void main() {
  test('detail trace result messages preserve target ordinal', () {
    final script = buildOfficialInvoiceDetailEnrichmentTraceScript(
      scope: OfficialInvoiceDetailSelectionScope.currentPage,
      handlerName: 'traceHandler',
    );

    expect(script, contains('ordinal: index + 1, result: base'));
    expect(
      RegExp(r"type: 'result', ordinal: index \+ 1")
          .allMatches(script)
          .length,
      7,
    );
    expect(script, isNot(contains("send({ type: 'result', result: base })")));
  });

  test(
    'runtime resolves progress and results by ordinal before invoice number',
    () {
      final source = File(
        'lib/features/invoice/lab/flutter_landing_webview_session_runtime.dart',
      ).readAsStringSync();

      expect(source, contains('_detailActiveOrdinal'));
      expect(source, contains('ordinal: progress.current'));
      expect(source, contains('ordinal: resultOrdinal'));
      expect(source, contains('item.ordinal == ordinal'));
    },
  );
}
