import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/dashboard/dashboard_page.dart';

void main() {
  testWidgets('Dashboard keeps compact entry shortcuts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DashboardPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('日常帳本'), findsOneWidget);
    expect(find.text('速記'), findsOneWidget);
    expect(find.text('發票'), findsOneWidget);
    expect(find.text('商品'), findsOneWidget);
    expect(find.text('還款'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);

    expect(find.text('拍照'), findsNothing);
    expect(find.text('拍照記帳'), findsNothing);
    expect(find.text('掃描發票'), findsNothing);
    expect(find.text('拍商品'), findsNothing);
  });
}
