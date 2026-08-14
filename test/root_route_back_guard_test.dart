import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/routing/root_route_back_guard.dart';

void main() {
  testWidgets('root route shows fallback button and invokes fallback', (
    tester,
  ) async {
    var fallbackCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RootRouteBackGuard(
          onFallback: () => fallbackCalls += 1,
          child: Scaffold(appBar: AppBar(title: const Text('帳戶管理'))),
        ),
      ),
    );

    expect(find.byKey(RootRouteBackGuard.fallbackButtonKey), findsOneWidget);
    await tester.tap(find.byKey(RootRouteBackGuard.fallbackButtonKey));
    expect(fallbackCalls, 1);
  });

  testWidgets('system back on root route invokes dashboard fallback', (
    tester,
  ) async {
    var fallbackCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RootRouteBackGuard(
          onFallback: () => fallbackCalls += 1,
          child: const Scaffold(),
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(fallbackCalls, 1);
  });

  testWidgets('nested route uses normal navigator pop without overlay', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('首頁')),
      ),
    );

    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RootRouteBackGuard(
          child: Scaffold(appBar: AppBar(title: const Text('帳戶管理'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RootRouteBackGuard.fallbackButtonKey), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('首頁'), findsOneWidget);
  });
}
