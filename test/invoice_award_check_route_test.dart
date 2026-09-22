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
    expect(
      find.text('目前沒有可顯示的中獎結果。中獎比對只使用已驗證的官方資料並在裝置本機完成。'),
      findsOneWidget,
    );
    expect(find.textContaining('兌獎'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
