import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/app.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_page.dart';
import 'package:my_finance_app/main.dart' show buildProductionApp;
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  test('installed main and release witness share the exact ProviderScope root', () {
    final root = buildProductionApp();
    expect(root, isA<ProviderScope>());
    expect((root as ProviderScope).child, isA<MyFinanceApp>());
  });

  test('canonical router has exactly one production award-check route', () {
    final matches = buildAppRoutes()
        .whereType<GoRoute>()
        .where((route) => route.path == InvoiceAwardCheckPage.routePath)
        .toList(growable: false);
    expect(matches, hasLength(1));
    expect(matches.single.name, InvoiceAwardCheckPage.routeName);
    expect(matches.single.builder, isNotNull);
  });
  test('full-path synthetic fixture is excluded from production root and page', () {
    final main = File('lib/main.dart').readAsStringSync();
    final page = File('lib/features/invoice/invoice_award_production_page.dart')
        .readAsStringSync();
    expect(main, isNot(contains('C500_FULL_PATH_WITNESS')));
    expect(page, isNot(contains('C500_FULL_PATH_WITNESS')));
    expect(main, isNot(contains('c500_release_witness.dart')));
    expect(page, isNot(contains('c500_release_witness.dart')));
  });
}
