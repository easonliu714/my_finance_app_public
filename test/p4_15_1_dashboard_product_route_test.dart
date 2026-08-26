import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/product/product_capture_page.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  testWidgets('Dashboard product shortcut opens product capture page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final routes = buildAppRoutes();
    final productRoute = routes.whereType<GoRoute>().singleWhere(
          (route) => route.name == ProductCapturePage.routeName,
        );
    expect(productRoute.path, ProductCapturePage.routePath);

    final router = GoRouter(initialLocation: '/', routes: routes);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('商品'));
    // Navigation is the contract under test. ProductCapturePage also starts
    // platform/repository-backed reference-data loads, so a global
    // pumpAndSettle can wait on unrelated asynchronous work indefinitely.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ProductCapturePage), findsOneWidget);
    expect(find.text('拍商品'), findsOneWidget);
  });
}
