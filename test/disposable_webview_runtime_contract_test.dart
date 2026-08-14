import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime contains every required cleanup operation', () {
    final source = File(
      'lib/features/invoice/lab/flutter_disposable_webview_session_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('clearCookies'));
    expect(source, contains('clearCache'));
    expect(source, contains('clearLocalStorage'));
    expect(source, contains('sessionStorage.clear'));
    expect(source, contains('localStorage.clear'));
    expect(source, contains('loadHtmlString'));
    expect(source, contains("initialUri.scheme.toLowerCase() != 'https'"));
  });

  test('runtime exposes only the bounded structural probe bridge', () {
    final source = File(
      'lib/features/invoice/lab/flutter_disposable_webview_session_runtime.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('addJavaScriptChannel')));
    expect(source, contains('runJavaScriptReturningResult'));
    expect(
      source,
      contains('buildAuthenticatedSelectorCapabilityProbeScript'),
    );
    expect(source, isNot(contains('setOnConsoleMessage')));
    expect(source, isNot(contains('authorization')));
    expect(source, isNot(contains('password')));
    expect(source, isNot(contains('CloudInvoiceCandidate')));
    expect(source, isNot(contains('TransactionRepository')));
  });

  test('lab shell is not exposed through the production router', () {
    final routerSource = File(
      'lib/routing/app_router.dart',
    ).readAsStringSync();

    expect(routerSource, isNot(contains('DisposableWebViewSessionShell')));
    expect(routerSource, isNot(contains('AuthenticatedSelectorProbePanel')));
    expect(routerSource, isNot(contains('p4-lab')));
    expect(routerSource, isNot(contains('webview-session')));
  });

  test('official WebView dependency is exactly pinned', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('webview_flutter: 4.13.1'));
    expect(pubspec, isNot(contains('webview_flutter: ^')));
  });
}
