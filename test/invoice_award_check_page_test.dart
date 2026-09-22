import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_page.dart';

void main() {
  testWidgets('manual refresh is absent without explicit caller authority',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InvoiceAwardCheckPage(presentations: []),
      ),
    );

    expect(find.byTooltip('手動更新官方中獎資料'), findsNothing);
  });

  testWidgets('manual refresh emits one explicit user intent', (tester) async {
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InvoiceAwardCheckPage(
          presentations: const [],
          onManualRefresh: () => refreshCount += 1,
        ),
      ),
    );

    await tester.tap(find.byTooltip('手動更新官方中獎資料'));
    await tester.pump();

    expect(refreshCount, 1);
  });

  testWidgets('manual refresh is disabled while acquisition is in progress',
      (tester) async {
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InvoiceAwardCheckPage(
          presentations: const [],
          isRefreshing: true,
          onManualRefresh: () => refreshCount += 1,
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('手動更新官方中獎資料'),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(refreshCount, 0);
  });
}
