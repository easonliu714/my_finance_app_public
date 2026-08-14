import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_config.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_entry_overlay.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_page.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_webview_page.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  test('private LAB compile-time gate defaults to false', () {
    expect(PrivateCloudInvoiceLabConfig.enabled, isFalse);
  });

  test('validation version matches current pubspec package version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versionMatch = RegExp(
      r'^version:\s*([^\s]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(versionMatch, isNotNull);
    expect(
      PrivateCloudInvoiceLabConfig.validationVersion,
      versionMatch!.group(1),
    );
  });

  test('official landing URI is stable and query family is bounded', () {
    final uri = PrivateCloudInvoiceLabConfig.officialLandingUri;
    expect(uri.scheme, 'https');
    expect(uri.host, 'www.einvoice.nat.gov.tw');
    expect(uri.path, '/portal/btc/mobile');
    expect(uri.path, isNot(contains('/btc502w')));
    expect(
      PrivateCloudInvoiceLabConfig.approvedQueryPathFragment,
      '/btc502w',
    );
  });

  test('disabled routes hide full LAB but retain official WebView import', () {
    final routes = buildAppRoutes(privateCloudInvoiceLabEnabled: false);
    expect(
      _paths(routes),
      isNot(contains(PrivateCloudInvoiceLabPage.routePath)),
    );
    expect(
      _paths(routes)
          .where((path) =>
              path == PrivateCloudInvoiceLabWebViewPage.routePath),
      hasLength(1),
    );
  });

  test('enabled routes contain one full LAB and one WebView path', () {
    final routes = buildAppRoutes(privateCloudInvoiceLabEnabled: true);
    expect(
      _paths(routes)
          .where((path) => path == PrivateCloudInvoiceLabPage.routePath),
      hasLength(1),
    );
    expect(
      _paths(routes)
          .where((path) =>
              path == PrivateCloudInvoiceLabWebViewPage.routePath),
      hasLength(1),
    );
  });

  testWidgets('entry overlay invokes explicit open callback', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateCloudInvoiceLabEntryOverlay(
          onOpen: () => opened = true,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    expect(
      find.byKey(PrivateCloudInvoiceLabEntryOverlay.entryKey),
      findsOneWidget,
    );
    await tester.tap(find.byKey(PrivateCloudInvoiceLabEntryOverlay.entryKey));
    expect(opened, isTrue);
  });

  testWidgets('LAB exposes draft promotion review entry', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateCloudInvoiceLabPage(
          onOpenDraftPromotion: () => opened = true,
        ),
      ),
    );
    await tester.pump();
    final button = find.byKey(
      PrivateCloudInvoiceLabPage.draftPromotionButtonKey,
    );
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(opened, isTrue);
  });
}

List<String> _paths(List<RouteBase> routes) {
  return routes.whereType<GoRoute>().map((route) => route.path).toList();
}
