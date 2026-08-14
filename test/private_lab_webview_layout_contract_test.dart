import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe panel is collapsed until explicitly expanded', () {
    final source = File(
      'lib/features/invoice/lab/disposable_webview_session_shell.dart',
    ).readAsStringSync();

    expect(source, contains('probeExpansionKey'));
    expect(source, contains('ExpansionTile('));
    expect(source, contains('initiallyExpanded: false'));
    expect(source, contains('maintainState: true'));
    expect(source, contains('平時收合以保留網頁操作空間'));
  });

  test('keyboard hides LAB chrome and preserves WebView input area', () {
    final source = File(
      'lib/features/invoice/lab/disposable_webview_session_shell.dart',
    ).readAsStringSync();

    expect(source, contains('MediaQuery.viewInsetsOf(context).bottom > 0'));
    expect(source, contains('if (!keyboardVisible)'));
    expect(source, contains('runtimeViewKey'));
  });

  test('landing runtime uses the complete Chrome desktop-site profile', () {
    final source = File(
      'lib/features/invoice/lab/flutter_landing_webview_session_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('onLoadStop'));
    expect(source, contains('_applyCompatibilityScripts(controller, url)'));
    expect(source, contains('desktopOfficialPortalUserAgent'));
    expect(source, contains('userAgent: desktopOfficialPortalUserAgent'));
    expect(
      source,
      contains('preferredContentMode: UserPreferredContentMode.DESKTOP'),
    );
    expect(source, contains('useWideViewPort: true'));
    expect(source, contains('loadWithOverviewMode: true'));
    expect(source, contains('initialScale: 0'));
    expect(source, contains('supportZoom: true'));
    expect(source, contains('_isApprovedQueryRoute(uri)'));
    expect(source, contains('buildOfficialQueryResultDesktopLayoutScript'));
    expect(source, contains('buildOfficialMobileViewportCompatibilityScript'));
    expect(source, contains('buildOfficialMobileFitWidthScript'));
    expect(
      source,
      contains('ContextAwareOfficialMobileSelectorCapabilityReportParser'),
    );
  });
}
