import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_entry_page.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_page.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  testWidgets('Dashboard invoice shortcut opens stable capture entry route',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final routes = buildAppRoutes();
    final invoiceRoute = routes.whereType<GoRoute>().singleWhere(
          (route) => route.name == InvoiceCapturePage.routeName,
        );
    expect(invoiceRoute.path, InvoiceCapturePage.routePath);

    final router = GoRouter(initialLocation: '/', routes: routes);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('發票'), findsOneWidget);
    expect(find.text('商品'), findsOneWidget);
    expect(find.text('拍照'), findsNothing);

    await tester.tap(find.text('發票'));
    await tester.pumpAndSettle();

    expect(find.byType(InvoiceCaptureEntryPage), findsOneWidget);
    expect(find.text('發票辨識'), findsOneWidget);
    expect(find.text('Live 即時辨識'), findsOneWidget);
    expect(find.text('從圖片讀取'), findsOneWidget);
    expect(find.text('拍照／相簿辨識'), findsNothing);
  });
}
