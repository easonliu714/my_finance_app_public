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
      routes: buildAppRoutes(privateCloudInvoiceLabEnabled: false),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('統一發票中獎檢查'), findsOneWidget);
    expect(find.textContaining('115年07-08月開獎：2026-09-25'), findsOneWidget);
    expect(find.text('手動更新官方中獎資料'), findsOneWidget);
    expect(find.textContaining('尚未更新官方 115年07-08月 中獎資料'), findsOneWidget);
    expect(find.textContaining('不上傳發票或記帳內容'), findsOneWidget);
    expect(find.textContaining('不是兌獎、領獎或自動匯款平台'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
