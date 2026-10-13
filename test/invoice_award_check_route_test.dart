import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_page.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  testWidgets('Award Check route is reachable and remains read-only',
      (tester) async {
    final router = GoRouter(
      initialLocation: InvoiceAwardCheckPage.routePath,
      routes: buildAppRoutes(
        privateCloudInvoiceLabEnabled: false,
        invoiceAwardClock: () => DateTime(2026, 9, 23, 12),
      ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('統一發票中獎檢查'), findsOneWidget);
    expect(
      find.byKey(const Key('invoice_award_period_selector')),
      findsOneWidget,
    );
    // The picker contains only award periods; redemption detail lives below.
    final periodSelector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('invoice_award_period_selector')),
    );
    final labels = periodSelector.items!
        .map((item) => (item.child as Text).data!)
        .toList();
    expect(labels, containsAll(<String>['115年07-08月', '115年05-06月']));
    expect(labels.every((label) => !label.contains('兌獎')), isTrue);
    expect(find.text('115年05-06月'), findsWidgets);
    expect(find.textContaining('兌獎資訊：兌獎期間內'), findsOneWidget);
    expect(find.text('授權更新並檢查既有交易'), findsOneWidget);
    expect(
      find.textContaining('尚未更新官方 115年05-06月 中獎資料'),
      findsOneWidget,
    );
    expect(find.textContaining('雲端專屬獎尚未更新'), findsOneWidget);
    // Policy text must remain hidden until its explicitly labeled help opens.
    expect(find.textContaining('不上傳發票或記帳內容'), findsNothing);
    expect(find.textContaining('不是兌獎、領獎或自動匯款平台'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    // Long instructions moved under the explicit '?' disclosure.
    final officialSourceHelp = find.byTooltip('開獎期別與官方來源說明');
    expect(officialSourceHelp, findsOneWidget);
    await tester.tap(officialSourceHelp);
    await tester.pumpAndSettle();
    expect(find.textContaining('不上傳發票或記帳內容'), findsOneWidget);
    expect(find.textContaining('大型 PDF'), findsOneWidget);
  });
}
