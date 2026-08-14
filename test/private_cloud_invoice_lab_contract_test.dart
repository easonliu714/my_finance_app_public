import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smoke service can only create a non-formal draft', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_smoke_service.dart',
    ).readAsStringSync();

    expect(source, contains('CloudInvoiceReconciliationOutcome.createNewDraft'));
    expect(source, contains('merchantProposalConfirmed: false'));
    expect(source, contains('currencyCode: null'));
    expect(source, contains('CloudInvoiceTimePrecision.dateOnly'));
    expect(source, isNot(contains('replaceExisting')));
    expect(source, isNot(contains('enrichExisting')));
    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('MerchantRepository')));
  });

  test('private WebView preserves transient pauses and uses parsed handoff', () {
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_webview_page.dart',
    ).readAsStringSync();
    final lifecyclePolicy = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_lifecycle_policy.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/invoice/lab/disposable_webview_session.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/features/invoice/lab/flutter_landing_webview_session_runtime.dart',
    ).readAsStringSync();
    final blobCapture = File(
      'lib/features/invoice/lab/official_page_generated_blob_capture.dart',
    ).readAsStringSync();
    final downloader = File(
      'lib/features/invoice/lab/ephemeral_authenticated_csv_download.dart',
    ).readAsStringSync();
    final originPolicy = File(
      'lib/features/invoice/lab/official_portal_origin_policy.dart',
    ).readAsStringSync();

    expect(page, contains('WidgetsBindingObserver'));
    expect(page, contains('didChangeAppLifecycleState'));
    expect(page, contains('PrivateCloudInvoiceLabLifecyclePolicy.dispositionFor'));
    expect(page, contains('PrivateCloudInvoiceLabLifecycleDisposition.cancel'));
    expect(page, isNot(contains('_backgroundCancelGrace')));
    expect(page, isNot(contains('_backgroundCancelEpoch')));
    expect(page, isNot(contains('_scheduleBackgroundCancel')));
    expect(page, contains('FlutterLandingWebViewSessionRuntime'));
    expect(page, contains('EphemeralCsvDownloadResultPage'));
    expect(page, contains('Expanded('));
    expect(page, contains('PopScope<Object?>'));
    expect(page, contains('_requestPopAfterCleanup'));
    expect(page, contains('_cancelForSystemBack'));
    expect(page, contains('短暫鎖定螢幕或切換 App 不視為取消'));
    expect(page, isNot(contains('DisposableWebViewSessionShell(')));

    expect(lifecyclePolicy, contains('AppLifecycleState.detached'));
    expect(
      lifecyclePolicy,
      contains('PrivateCloudInvoiceLabLifecycleDisposition.cancel'),
    );
    expect(
      lifecyclePolicy,
      contains('PrivateCloudInvoiceLabLifecycleDisposition.preserve'),
    );
    expect(lifecyclePolicy, isNot(contains('Timer')));
    expect(lifecyclePolicy, isNot(contains('Duration(seconds: 8)')));

    expect(controller, contains('Future<void> cancel() => _endSession();'));
    expect(
      controller,
      isNot(contains('WidgetsBinding.instance.lifecycleState')),
    );
    expect(controller, contains('cleanupTimeout'));
    expect(controller, contains('SESSION_CLEANUP_TIMEOUT'));
    expect(controller, contains('prepareOfficialQueryPageForExport'));

    expect(runtime, contains('InAppWebView('));
    expect(runtime, contains('onDownloadStarting'));
    expect(runtime, isNot(contains('onDownloadStartRequest')));
    expect(runtime, contains('DownloadStartResponse('));
    expect(runtime, contains('handled: true'));
    expect(runtime, contains('DownloadStartResponseAction.CANCEL'));
    expect(runtime, contains('useOnDownloadStart: true'));
    expect(runtime, contains('CookieManager'));
    expect(runtime, contains('getCookies('));
    expect(runtime, contains('EphemeralAuthenticatedCsvDownloadService'));
    expect(runtime, contains('PageGeneratedCsvParser'));
    expect(runtime, contains('CSV_DOWNLOAD_EXPLICIT_TAP_REQUIRED'));
    expect(runtime, contains("scheme == 'data'"));
    expect(runtime, contains("scheme == 'blob'"));
    expect(runtime, contains('CSV_DOWNLOAD_SCHEME_OTHER'));
    expect(runtime, contains('CSV_DOWNLOAD_HOST_NOT_APPROVED'));
    expect(runtime, contains('CSV_BLOB_PAGE_NOT_APPROVED'));
    expect(runtime, contains('CSV_BLOB_NOT_CAPTURED'));
    expect(runtime, contains('_maxGeneratedBytes'));
    expect(runtime, contains('buildOfficialPageGeneratedBlobReadScript'));
    expect(runtime, contains("'/portal/btc/mobile/btc502w'"));
    expect(runtime, contains('buildOfficialQueryResultSelectorProbeScript'));
    expect(runtime, contains('buildOfficialMobileViewportCompatibilityScript'));
    expect(runtime, contains('buildOfficialMobileFitWidthScript'));
    expect(runtime, contains('buildOfficialQueryResultDesktopLayoutScript'));
    expect(runtime, contains('buildOfficialQueryPagePreparationScript'));
    expect(runtime, contains('buildOfficialQueryPageFinalizePreparationScript'));
    expect(runtime, contains('useWideViewPort: true'));
    expect(runtime, contains('supportZoom: true'));
    expect(runtime, contains('_cleanupStepTimeout'));
    expect(runtime, contains('action().timeout(_cleanupStepTimeout)'));
    expect(runtime, contains('_attemptBestEffort'));
    expect(runtime, isNot(contains('controller.clearHistory')));
    expect(runtime, isNot(contains("baseUrl: WebUri('about:blank')")));
    expect(runtime, contains('deleteAllCookies'));
    expect(runtime, contains('deleteAllData'));

    expect(blobCapture, contains('createObjectURL'));
    expect(blobCapture, contains('chunkSize = 65536'));
    expect(blobCapture, contains('CSV_BLOB_NOT_CAPTURED'));
    expect(blobCapture, contains('maximumBytes'));

    expect(originPolicy, contains("'einvoice.nat.gov.tw'"));
    expect(originPolicy, contains("endsWith('.\$officialPortalRootDomain')"));
    expect(downloader, contains('isApprovedOfficialPortalHost'));
    expect(downloader, contains("uri.scheme.toLowerCase() != 'https'"));
    expect(downloader, contains('10 * 1024 * 1024'));
    expect(downloader, contains('OfficialCloudInvoiceCsvAdapter'));
    expect(downloader, contains('CSV_SIGNATURE_INVALID'));
    expect(downloader, contains('temporaryFile'));
    expect(downloader, contains('_deleteQuietly'));
    expect(downloader, isNot(contains('DownloadManager')));
    expect(downloader, isNot(contains('Timer.periodic')));
  });

  test('public CI retains LAB gate and excludes signing capability', () {
    final source = File(
      '.github/workflows/flutter_android_ci.yml',
    ).readAsStringSync();

    expect(source, contains('enable_private_cloud_invoice_lab:'));
    expect(source, contains("default: 'false'"));
    expect(
      source,
      contains('--dart-define=ENABLE_PRIVATE_CLOUD_INVOICE_LAB=false'),
    );
    expect(
      source,
      contains('--dart-define=ENABLE_PRIVATE_CLOUD_INVOICE_LAB='),
    );
    expect(source, contains('Build manual debug APK'));
    expect(source, contains('android.permission.INTERNET'));
    expect(source, contains('permissions:'));
    expect(source, contains('contents: read'));
    expect(source, contains('persist-credentials: false'));
    expect(source, isNot(contains('ANDROID_KEYSTORE_BASE64')));
    expect(source, isNot(contains('ANDROID_KEYSTORE_PASSWORD')));
    expect(source, isNot(contains('ANDROID_KEY_ALIAS')));
    expect(source, isNot(contains('ANDROID_KEY_PASSWORD')));
    expect(source, isNot(contains('flutter build apk --release')));
    expect(source, isNot(contains('Prepare signing files')));
    expect(source, isNot(contains('Verify signed release manifest permissions')));
  });

  test('router gates full LAB, exposes official WebView, and protects root', () {
    final source = File('lib/routing/app_router.dart').readAsStringSync();

    expect(source, contains('privateCloudInvoiceLabEnabled'));
    expect(source, contains('if (privateCloudInvoiceLabEnabled)'));
    expect(source, contains('PrivateCloudInvoiceLabPage.routePath'));
    expect(source, contains('PrivateCloudInvoiceLabWebViewPage.routePath'));
    expect(
      source,
      contains('name: PrivateCloudInvoiceLabWebViewPage.routeName'),
    );
    expect(source, isNot(contains('PrivateCloudInvoiceLabEntryOverlay')));
    expect(
      source,
      isNot(contains('if (!privateCloudInvoiceLabEnabled) return page')),
    );
    expect(source, contains('RootRouteBackGuard(child: AccountPage())'));
  });

  test('no background or automatic formal execution is introduced', () {
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_webview_page.dart',
    ).readAsStringSync();
    final downloader = File(
      'lib/features/invoice/lab/ephemeral_authenticated_csv_download.dart',
    ).readAsStringSync();
    final combined = '$page\n$downloader';

    expect(combined, isNot(contains('Timer.periodic')));
    expect(combined, isNot(contains('Workmanager')));
    expect(combined, isNot(contains('DownloadManager')));
    expect(combined, isNot(contains('create formal transaction')));
  });
}
