import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_entry_button.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_page.dart';

void main() {
  testWidgets('Reports award entry opens the governed Award Check route',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            appBar: AppBar(
              actions: const <Widget>[InvoiceAwardCheckEntryButton()],
            ),
            body: const Text('reports'),
          ),
        ),
        GoRoute(
          path: InvoiceAwardCheckPage.routePath,
          name: InvoiceAwardCheckPage.routeName,
          builder: (context, state) =>
              const Scaffold(body: Text('award-check-target')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(
      find.byKey(InvoiceAwardCheckEntryButton.buttonKey),
      findsOneWidget,
    );
    expect(find.byTooltip('統一發票對獎'), findsOneWidget);

    await tester.tap(find.byKey(InvoiceAwardCheckEntryButton.buttonKey));
    await tester.pumpAndSettle();

    expect(find.text('award-check-target'), findsOneWidget);
  });
}
