import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/app.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  testWidgets('My route renders production backup migration center',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    appRouter.go('/my');
    await tester.pumpWidget(const ProviderScope(child: MyFinanceApp()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('我的'), findsAtLeastNWidgets(1));
    expect(find.text('備份與移轉'), findsOneWidget);
    expect(find.text('備份與換機移轉中心'), findsNothing);
    expect(find.text('目前可用功能'), findsNothing);
    expect(find.text('AI 模型設定'), findsNothing);
    expect(find.text('影像輔助記帳'), findsNothing);
    expect(find.text('雲端發票與對獎治理'), findsNothing);

    await tester.tap(find.byTooltip('備份與移轉 說明'));
    // P4.20.1 registry status can legitimately keep an indeterminate progress
    // indicator alive while the initial local snapshot read is pending. Use a
    // bounded pump so this navigation test does not require global animation
    // quiescence unrelated to the dialog contract under test.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('備份與移轉說明'), findsOneWidget);
    await tester.tap(find.text('了解'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(
      find.text('備份提醒'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('備份提醒'), findsOneWidget);
    expect(find.text('備份通知'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('完整還原'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('完整備份'), findsOneWidget);
    expect(find.text('完整還原'), findsOneWidget);
  });
}
