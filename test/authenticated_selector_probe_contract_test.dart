import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/authenticated_selector_capability_probe.dart';

void main() {
  test('allowlist defines every capability exactly once', () {
    final capabilities = officialQuerySelectorAllowlist
        .map((spec) => spec.capability)
        .toList();

    expect(capabilities.toSet(), AuthenticatedSelectorCapability.values.toSet());
    expect(capabilities.length, capabilities.toSet().length);
    expect(
      officialQuerySelectorAllowlist.every(
        (spec) => spec.maximumMatches == 1 && spec.selectors.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('allowlist contains no unrestricted selector patterns', () {
    for (final spec in officialQuerySelectorAllowlist) {
      for (final selector in spec.selectors) {
        expect(selector.trim(), isNotEmpty);
        expect(selector, isNot(contains('*=')));
        expect(selector, isNot(equals('*')));
        expect(selector, isNot(equals('input')));
        expect(selector, isNot(equals('button')));
        expect(selector, isNot(equals('select')));
        expect(selector, isNot(equals('table')));
        expect(selector, isNot(contains(':contains(')));
      }
    }
  });

  test('probe source has no persistence or financial write dependency', () {
    final source = File(
      'lib/features/invoice/lab/authenticated_selector_capability_probe.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/features/invoice/lab/flutter_disposable_webview_session_runtime.dart',
    ).readAsStringSync();

    for (final text in <String>[source, runtime]) {
      expect(text, isNot(contains('TransactionRepository')));
      expect(text, isNot(contains('AccountRepository')));
      expect(text, isNot(contains('CloudInvoiceStagingAdapter')));
      expect(text, isNot(contains('CloudInvoiceCandidate')));
      expect(text, isNot(contains('SharedPreferences')));
      expect(text, isNot(contains('sqflite')));
    }
  });

  test('probe script avoids unrestricted page-content access', () {
    final script = buildAuthenticatedSelectorCapabilityProbeScript();

    expect(script, isNot(contains('document.body')));
    expect(script, isNot(contains('document.documentElement')));
    expect(script, isNot(contains('getElementsByTagName')));
    expect(script, isNot(contains('innerHTML')));
    expect(script, isNot(contains('outerHTML')));
    expect(script, isNot(contains('document.cookie')));
    expect(script, isNot(contains('window.localStorage')));
    expect(script, isNot(contains('window.sessionStorage')));
    expect(script, isNot(contains('fetch(')));
    expect(script, isNot(contains('XMLHttpRequest')));
  });

  test('production router remains independent from LAB.3C', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(router, isNot(contains('AuthenticatedSelectorProbePanel')));
    expect(router, isNot(contains('AuthenticatedSelectorCapabilityReport')));
    expect(router, isNot(contains('selector-capability-probe')));
    expect(router, isNot(contains('p4-lab-3c')));
  });
}
