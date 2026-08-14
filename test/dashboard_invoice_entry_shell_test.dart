import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/dashboard/dashboard_invoice_entry_shell.dart';

void main() {
  testWidgets('Dashboard entry button is visible', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DashboardInvoiceEntryShell()),
      ),
    );
    await tester.pump();

    final finder = find.byKey(DashboardInvoiceEntryShell.cloudInvoiceReviewEntryKey);
    expect(finder, findsOneWidget);
    expect(tester.widget<FloatingActionButton>(finder).onPressed, isNotNull);
  });
}
