import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_inbox_page.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';

void main() {
  testWidgets('cloud invoice workbench exposes production WebView entry',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudInvoiceInboxPage(
          port: const _EmptyInboxPort(),
          onOpenWebView: () => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(CloudInvoiceInboxPage.webViewKey);
    expect(entry, findsOneWidget);
    expect(find.text('官方發票一次性匯入'), findsOneWidget);
    expect(find.text('開啟官方發票匯入'), findsOneWidget);

    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pump();
    expect(opened, isTrue);
  });
}

class _EmptyInboxPort implements CloudInvoiceInboxPort {
  const _EmptyInboxPort();

  @override
  Future<List<PrivateCloudInvoiceDraftCandidate>> listPendingDrafts() async {
    return const <PrivateCloudInvoiceDraftCandidate>[];
  }
}
