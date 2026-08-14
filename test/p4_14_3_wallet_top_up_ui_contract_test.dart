import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/account/wallet_top_up_hub_page.dart';
import 'package:my_finance_app/features/account/wallet_top_up_settings_page.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  test('P4.14.3 routes expose hub and account settings pages', () {
    final routes = buildAppRoutes()
        .whereType<GoRoute>()
        .map((route) => route.name)
        .toSet();

    expect(routes, contains(WalletTopUpHubPage.routeName));
    expect(routes, contains(WalletTopUpSettingsPage.routeName));
  });

  test('wallet top-up UI has no formal transaction write dependency', () {
    final files = <String>[
      'lib/features/account/wallet_top_up_hub_page.dart',
      'lib/features/account/wallet_top_up_settings_page.dart',
      'lib/features/account/wallet_top_up_ui_gateway.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('TransactionRepository')));
      expect(source, isNot(contains('transactionLedgerProvider')));
      expect(source, isNot(contains('upsertTransaction')));
      expect(source, isNot(contains('TransactionRecord(')));
    }
  });

  test('release-critical wallet controls keep explicit stable keys', () {
    final source = File(
      'lib/features/account/wallet_top_up_settings_page.dart',
    ).readAsStringSync();

    expect(source, contains('wallet-top-up-enable-switch'));
    expect(source, contains('wallet-top-up-funding-account'));
    expect(source, contains('wallet-top-up-threshold'));
    expect(source, contains('wallet-top-up-amount-mode'));
    expect(source, contains('wallet-top-up-target-amount'));
    expect(source, contains('wallet-top-up-cooldown-hours'));
    expect(source, contains('wallet-top-up-save'));
    expect(source, contains('wallet-top-up-evaluate'));
  });

  test('non-provider wording remains explicit', () {
    final hub = File(
      'lib/features/account/wallet_top_up_hub_page.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/account/wallet_top_up_settings_page.dart',
    ).readAsStringSync();

    expect(hub, contains('不會連線至銀行或支付服務'));
    expect(hub, contains('不會自動建立正式交易'));
    expect(settings, contains('不會連線至銀行或支付服務'));
    expect(settings, contains('不會建立正式交易'));
  });
}
