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
    final sourceCustody = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/PlatformSourceSnapshotCustody.kt',
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
    expect(
      lifecycleSource,
      contains('最後收到的背景進度（尚未完成驗證）'),
    );
    expect(lifecycleSource, contains('_cloudTierSummaries[tier]'));
    expect(
      lifecycleSource,
      isNot(contains('正在同步背景雲端獎比對進度與結果。')),
    );
    // Diagnostics must distinguish opening an 87,000-page PDF from slow
    // per-page searches. No timeout or SHA skip may be used as a workaround.
    expect(
      foregroundSource,
      contains("'PLATFORM_RENDERER_OPEN_WAIT' =>"),
    );
    expect(
      foregroundSource,
      contains("'PLATFORM_RENDERER_PAGE_BEGIN' =>"),
    );
    expect(
      foregroundSource,
      contains("'PLATFORM_RENDERER_CANDIDATE_SEARCH' =>"),
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
    expect(largeWorkerSource, contains('PlatformSourceSnapshotCustody.capture('));
    expect(largeWorkerSource, contains('var descriptor: ParcelFileDescriptor? = custody.descriptor'));
    expect(sourceCustody, contains('ParcelFileDescriptor.MODE_READ_ONLY'));
    expect(sourceCustody, contains('LinkOption.NOFOLLOW_LINKS'));
    expect(sourceCustody, contains('Files.delete(snapshot)'));
    expect(sourceCustody, contains('SOURCE_CUSTODY_SHA256_MISMATCH'));
    // Verify the nullable snapshot FD is checked before renderer ownership.
    expect(
      largeWorkerSource,
      contains('val rendererDescriptor = descriptor ?: throw IOException("SOURCE_CUSTODY_DESCRIPTOR_MISSING")'),
    );
    expect(largeWorkerSource, contains('renderer = PdfRenderer(rendererDescriptor)'));
    final guardAt = largeWorkerSource.indexOf(
      'val rendererDescriptor = descriptor ?: throw IOException(',
    );
    final rendererAt = largeWorkerSource.indexOf('renderer = PdfRenderer(rendererDescriptor)');
    expect(guardAt, greaterThanOrEqualTo(0));
    expect(rendererAt, greaterThan(guardAt));
    final handoffAt = largeWorkerSource.indexOf('descriptor = null', rendererAt);
    expect(handoffAt, greaterThan(rendererAt));
    expect(largeWorkerSource, contains('try { renderer?.close() }'));
    expect(largeWorkerSource, contains('try { descriptor?.close() }'));
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
    // Screen-off mitigation retains native CPU progress but is bounded.
    // The worker must still fail closed if Android kills its process.
    expect(pluginManifest, contains('android.permission.WAKE_LOCK'));
    expect(largeWorkerSource, contains('PowerManager.PARTIAL_WAKE_LOCK'));
    expect(largeWorkerSource, contains('CANDIDATE_WAKE_LOCK_MAX_MS'));
    expect(largeWorkerSource, contains('wakeLock.acquire('));
    expect(largeWorkerSource, contains('if (it.isHeld) it.release()'));
    expect(pluginSource, contains('getHistoricalProcessExitReasons'));
    expect(pluginSource, contains('"exitReasonCode" to exitReasonCode'));
    expect(candidateSource, contains("'_OS_EXIT_"));

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
