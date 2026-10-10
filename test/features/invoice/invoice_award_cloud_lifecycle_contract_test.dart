import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud 500 lifecycle is bounded and retry-safe', () {
    final candidateSource = File(
      'lib/features/invoice/invoice_award_cloud_candidate_scope.dart',
    ).readAsStringSync();
    final foregroundSource = File(
      'lib/features/invoice/invoice_award_cloud_foreground_acquisition.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    final pluginGradle = File(
      'packages/flutter_pdf_text/android/build.gradle',
    ).readAsStringSync();
    final pluginSource = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/PdfTextPlugin.kt',
    ).readAsStringSync();
    final largeWorkerSource = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/PlatformPdfCandidateWorkerService.kt',
    ).readAsStringSync();
    final pluginManifest = File(
      'packages/flutter_pdf_text/android/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(candidateSource, contains('CloudAwardCandidateLookupCancellation'));
    expect(candidateSource, contains("'openPdfiumSession'"));
    expect(candidateSource, contains("'closePdfiumSession'"));
    expect(candidateSource, contains('candidateBatchSize = 8'));
    expect(
      candidateSource,
      contains('crashIsolatedPdfiumPdfBytes = 120 * 1024 * 1024'),
    );
    expect(candidateSource, contains("'startPlatformCandidateWorker'"));
    expect(
      candidateSource,
      isNot(contains('CLOUD_AWARD_CANDIDATE_WORKER_STALE_HEARTBEAT_')),
    );
    expect(
      candidateSource,
      contains('workerHeartbeatProbeAfter = Duration(seconds: 15)'),
    );
    expect(
      candidateSource,
      contains("'getPlatformCandidateWorkerLiveness'"),
    );
    expect(
      candidateSource,
      contains('CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_'),
    );
    expect(
      candidateSource,
      isNot(contains('workerResultTimeout = Duration(seconds: 120)')),
    );
    expect(candidateSource, contains('_findMatchesCrashIsolated'));
    expect(candidateSource, contains('for (var batchStart = 0;'));
    expect(candidateSource, contains('uniquePagesRead'));
    expect(candidateSource, contains('toSet()'));
    expect(candidateSource, contains('..sort()'));
    expect(foregroundSource, contains('candidateScopedEmptyVerified'));
    expect(
      foregroundSource,
      contains(r'二分搜尋目前定位第 ${progress.pageNumber}/'),
    );
    expect(
      foregroundSource,
      contains(r'累計實際讀取 ${progress.pagesRead} 頁'),
    );
    expect(
      foregroundSource,
      contains('非逐頁掃描'),
    );
    expect(
      foregroundSource,
      contains('背景服務正在以 Android 系統 PDF 引擎開啟大型 PDF'),
    );
    expect(
      foregroundSource,
      contains('預估剩餘'),
    );
    expect(
      foregroundSource,
      contains('本期沒有可比對的雲端候選，略過大型 500 元獎 PDF'),
    );
    expect(pageSource, contains('with WidgetsBindingObserver'));
    expect(pageSource, contains('_ownsProcessRefresh'));
    final lifecycleStart =
        pageSource.indexOf('void didChangeAppLifecycleState(');
    final lifecycleEnd = pageSource.indexOf('DateTime _now()', lifecycleStart);
    expect(lifecycleStart, greaterThanOrEqualTo(0));
    expect(lifecycleEnd, greaterThan(lifecycleStart));
    final lifecycleSource =
        pageSource.substring(lifecycleStart, lifecycleEnd);
    expect(
      lifecycleSource,
      isNot(contains('_activeCloudCancellation?.cancel()')),
    );
    expect(
      lifecycleSource,
      isNot(contains('state == AppLifecycleState.inactive')),
    );
    expect(
      lifecycleSource,
      contains('state == AppLifecycleState.hidden'),
    );
    expect(
      lifecycleSource,
      contains('state == AppLifecycleState.paused'),
    );
    expect(
      lifecycleSource,
      contains('state == AppLifecycleState.resumed'),
    );
    final disposeStart = pageSource.indexOf('void dispose()');
    final disposeEnd =
        pageSource.indexOf('void didChangeAppLifecycleState', disposeStart);
    expect(disposeStart, greaterThanOrEqualTo(0));
    expect(disposeEnd, greaterThan(disposeStart));
    expect(
      pageSource.substring(disposeStart, disposeEnd),
      isNot(contains('_activeCloudCancellation?.cancel()')),
    );
    expect(pageSource, contains('on CloudAwardCandidateLookupCancelled'));
    expect(pageSource, contains('_cloudTierSummaries'));
    expect(pageSource, contains('雲端獎項解析摘要'));
    expect(pageSource, contains('_safeCloudFailureCode'));
    expect(
      foregroundSource,
      contains("const code = 'CLOUD_AWARD_CANDIDATE_LOOKUP_CANCELLED'"),
    );
    expect(
      foregroundSource,
      contains('Preserve already promoted earlier-tier authority'),
    );
    expect(pluginSource, contains('"startPlatformCandidateWorker"'));
    expect(pluginSource, contains('"getPlatformCandidateWorkerLiveness"'));
    expect(pluginSource, contains('ActivityManager'));
    expect(
      pluginSource,
      contains('PlatformPdfCandidateWorkerService::class.java'),
    );
    expect(pluginSource, contains('startForegroundService(intent)'));
    expect(largeWorkerSource, contains('android.graphics.pdf.PdfRenderer'));
    expect(largeWorkerSource, contains('ParcelFileDescriptor.MODE_READ_ONLY'));
    expect(largeWorkerSource, contains('renderer = PdfRenderer(descriptor)'));
    expect(
      largeWorkerSource,
      contains('renderer.openPage(pageNumber - 1)'),
    );
    expect(largeWorkerSource, contains('it.textContents'));
    expect(
      largeWorkerSource,
      contains('android-platform-pdfrenderer-candidate-search'),
    );
    expect(
      largeWorkerSource,
      contains('"PLATFORM_RENDERER_OPEN_BEGIN"'),
    );
    expect(
      largeWorkerSource,
      contains('"PLATFORM_RENDERER_OPEN_WAIT"'),
    );
    expect(
      largeWorkerSource,
      contains('OPEN_HEARTBEAT_INTERVAL_MS = 2_000L'),
    );
    expect(largeWorkerSource, contains('startForeground('));
    expect(largeWorkerSource, contains('NotificationChannel('));
    expect(
      largeWorkerSource,
      contains('"PLATFORM_RENDERER_CANDIDATE_SEARCH"'),
    );
    expect(
      RegExp(r'PDDocument\.load\s*\(').hasMatch(largeWorkerSource),
      isFalse,
    );
    expect(largeWorkerSource, isNot(contains('PdfiumCore')));
    expect(largeWorkerSource, isNot(contains('PDFTextStripper()')));
    expect(
      pluginManifest,
      contains('android:process=":platform_candidate_worker"'),
    );
    expect(pluginManifest, contains('android:exported="false"'));
    expect(pluginManifest, contains('android:foregroundServiceType="dataSync"'));
    expect(pluginManifest, contains('android:stopWithTask="false"'));
    expect(
      pluginManifest,
      contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'),
    );
    // <=120 MiB retains the previously proven PDFium path; >120 MiB is
    // guarded above to use platform PdfRenderer exclusively.
    expect(pluginGradle, contains('io.legere:pdfiumandroid:1.0.35'));
    expect(pluginGradle, contains('compileSdkVersion 36'));
  });
}
