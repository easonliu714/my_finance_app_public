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
    // The selected period is short; redemption details render separately.
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


  testWidgets('Award period help remains outside selector at phone width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    final periodRow =
        find.byKey(const Key('invoice_award_period_selector_row'));
    final selector = find.byKey(const Key('invoice_award_period_selector'));
    final help = find.byTooltip('開獎期別與官方來源說明');
    expect(periodRow, findsOneWidget);
    expect(find.descendant(of: periodRow, matching: selector), findsOneWidget);
    expect(find.descendant(of: periodRow, matching: help), findsOneWidget);
    expect(find.descendant(of: selector, matching: help), findsNothing);

    final selectorRect = tester.getRect(selector);
    final helpRect = tester.getRect(help);
    expect(selectorRect.right + 4, lessThanOrEqualTo(helpRect.left));
    expect(helpRect.right, lessThanOrEqualTo(360));

    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.textContaining('大型 PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Award period dropdown shows period-only option labels',
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

    expect(find.textContaining('兌獎資訊：兌獎期間內'), findsOneWidget);
    await tester.tap(find.byKey(const Key('invoice_award_period_selector')));
    await tester.pumpAndSettle();
    expect(find.text('115年07-08月'), findsWidgets);
    expect(find.text('115年05-06月'), findsWidgets);
  });

  testWidgets('award page floating back-to-top returns without changing data',
      (tester) async {
    // Simulate deep scrolling with a short viewport, without fabricating
    // official invoice candidates or changing production source.
    await tester.binding.setSurfaceSize(const Size(360, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    final scrollFinder = find.byKey(
      const Key('invoice_award_page_scroll_view'),
    );
    final scroll = tester.widget<SingleChildScrollView>(scrollFinder);
    final backToTop = find.byKey(const Key('invoice_award_back_to_top'));
    expect(scroll.controller, isNotNull);
    expect(backToTop, findsNothing);

    await tester.drag(scrollFinder, const Offset(0, -1100));
    await tester.pumpAndSettle();
    expect(scroll.controller!.position.maxScrollExtent, greaterThan(560));
    expect(scroll.controller!.offset, greaterThan(560));
    expect(backToTop, findsOneWidget);
    expect(find.byTooltip('回頁首'), findsOneWidget);

    await tester.tap(backToTop);
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, closeTo(0, 1));
    expect(backToTop, findsNothing);
    expect(
      find.textContaining('尚未更新官方 115年05-06月 中獎資料'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

}
