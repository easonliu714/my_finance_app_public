import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'authenticated_selector_capability_probe.dart';
import 'disposable_webview_session.dart';
import 'ephemeral_authenticated_csv_download.dart';
import 'official_invoice_detail_enrichment.dart';
import 'official_invoice_detail_enrichment_script.dart';
import 'official_invoice_detail_enrichment_trace_script.dart';
import 'official_mobile_selector_result_context.dart';
import 'official_page_generated_blob_capture.dart';
import 'official_portal_origin_policy.dart';
import 'official_query_page_preparation.dart';
import 'official_query_result_desktop_layout.dart';
import 'official_query_result_selector_probe.dart';
import 'page_generated_csv_parser.dart';
import 'private_cloud_invoice_csv_import_service.dart';

typedef EphemeralCsvReadyCallback = Future<void> Function(
  PrivateCloudInvoiceCsvSource source,
);
typedef EphemeralCsvDownloadErrorCallback = void Function(String errorCode);

/// One-shot official portal runtime with a native download-start callback.
class FlutterLandingWebViewSessionRuntime
    implements
        DisposableWebViewSessionRuntime,
        AuthenticatedSelectorCapabilityProbeRuntime,
        OfficialQueryPagePreparationRuntime,
        OfficialDetailPagePreparationRuntime,
        OfficialInvoiceDetailEnrichmentRuntime {
  FlutterLandingWebViewSessionRuntime({
    CookieManager? cookieManager,
    WebStorageManager? webStorageManager,
    AuthenticatedSelectorCapabilityReportParser? probeParser,
    EphemeralAuthenticatedCsvDownloadService? downloadService,
    PageGeneratedCsvParser? pageGeneratedCsvParser,
    EphemeralCsvReadyCallback? onCsvReady,
    EphemeralCsvDownloadErrorCallback? onDownloadError,
  })  : _cookieManager = cookieManager ?? CookieManager(),
        _webStorageManager = webStorageManager ?? WebStorageManager(),
        _probeParser = probeParser ??
            const ContextAwareOfficialMobileSelectorCapabilityReportParser(),
        _downloadService =
            downloadService ?? EphemeralAuthenticatedCsvDownloadService(),
        _pageGeneratedCsvParser =
            pageGeneratedCsvParser ?? const PageGeneratedCsvParser(),
        _onCsvReady = onCsvReady,
        _onDownloadError = onDownloadError;

  static const Duration _explicitGestureWindow = Duration(seconds: 10);
  static const Duration _cleanupStepTimeout = Duration(seconds: 2);
  static const String _queryRoutePrefix = '/portal/btc/mobile/btc502w';
  static const String _blobHandlerName = 'privateLabPageGeneratedCsv';
  static const String _detailHandlerName = 'privateLabOfficialInvoiceDetail';
  // Large foreground batches can exceed six minutes on a real device.
  // Keep a hard safety ceiling without truncating ordinary 50/100-item runs.
  static const Duration _detailBatchHardTimeout = Duration(minutes: 30);
  static const int _maxGeneratedBytes = 10 * 1024 * 1024;

  // Applied before the first navigation and retained for the disposable
  // session so the official portal creates its complete desktop result table.
  static const String desktopOfficialPortalUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  final CookieManager _cookieManager;
  final WebStorageManager _webStorageManager;
  final AuthenticatedSelectorCapabilityReportParser _probeParser;
  final EphemeralAuthenticatedCsvDownloadService _downloadService;
  final PageGeneratedCsvParser _pageGeneratedCsvParser;
  final EphemeralCsvReadyCallback? _onCsvReady;
  final EphemeralCsvDownloadErrorCallback? _onDownloadError;

  InAppWebViewController? _controller;
  Uri? _initialUri;
  DateTime? _lastPointerDownAt;
  bool _downloadInProgress = false;
  bool _pagePreparationPending = false;
  bool _disposed = false;

  bool _blobTransferArmed = false;
  BytesBuilder? _blobBytes;
  int _blobReceivedBytes = 0;
  int? _blobExpectedBytes;

  Completer<OfficialInvoiceDetailBatchResult>? _detailCompleter;
  List<OfficialInvoiceDetailEnrichment> _detailResults =
      <OfficialInvoiceDetailEnrichment>[];
  void Function(OfficialInvoiceDetailProgress progress)? _detailProgress;
  int _detailRequestedCount = 0;
  List<OfficialInvoiceDetailTraceItem> _detailTraces =
      <OfficialInvoiceDetailTraceItem>[];
  String? _detailActiveInvoiceNumber;
  int? _detailActiveOrdinal;

  @override
  Future<void> open(Uri initialUri) async {
    if (_disposed) throw StateError('SESSION_RUNTIME_DISPOSED');
    if (_initialUri != null) throw StateError('SESSION_ALREADY_OPEN');
    _validateNavigationUri(initialUri);
    await _clearBeforeOpen();
    _initialUri = initialUri;
  }

  @override
  Widget buildView() {
    final initialUri = _initialUri;
    if (initialUri == null) throw StateError('SESSION_NOT_OPEN');

    return Listener(
      key: ObjectKey(this),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lastPointerDownAt = DateTime.now(),
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(initialUri.toString())),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: desktopOfficialPortalUserAgent,
          preferredContentMode: UserPreferredContentMode.DESKTOP,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          initialScale: 0,
          supportZoom: true,
          builtInZoomControls: true,
          displayZoomControls: false,
          horizontalScrollBarEnabled: true,
          verticalScrollBarEnabled: true,
          useOnDownloadStart: true,
          useShouldOverrideUrlLoading: true,
          cacheEnabled: true,
          thirdPartyCookiesEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          mediaPlaybackRequiresUserGesture: true,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;
          controller.addJavaScriptHandler(
            handlerName: _blobHandlerName,
            callback: (arguments) {
              unawaited(_handleBlobBridgeMessage(arguments));
              return null;
            },
          );
          controller.addJavaScriptHandler(
            handlerName: _detailHandlerName,
            callback: (arguments) {
              _handleOfficialDetailBridgeMessage(arguments);
              return null;
            },
          );
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          if (navigationAction.hasGesture == true) {
            _lastPointerDownAt = DateTime.now();
          }
          final target = navigationAction.request.url;
          if (target == null) return NavigationActionPolicy.CANCEL;
          final uri = Uri.tryParse(target.toString());
          if (uri == null) return NavigationActionPolicy.CANCEL;
          if (_isAllowedNavigation(uri)) return NavigationActionPolicy.ALLOW;
          return NavigationActionPolicy.CANCEL;
        },
        onLoadStop: (controller, url) async {
          await _handleLoadStop(controller, url);
        },
        onDownloadStarting: (controller, request) {
          unawaited(_handleDownloadStart(controller, request));
          return DownloadStartResponse(
            handled: true,
            action: DownloadStartResponseAction.CANCEL,
          );
        },
      ),
    );
  }

  Future<void> _handleLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    await _applyCompatibilityScripts(controller, url);
    final uri = url == null ? null : Uri.tryParse(url.toString());
    if (!_isApprovedQueryRoute(uri)) return;

    await _attemptBestEffort(() async {
      await controller.evaluateJavascript(
        source: buildOfficialPageGeneratedBlobCaptureScript(),
      );
    });
    if (_pagePreparationPending) {
      await _attemptBestEffort(() async {
        await controller.evaluateJavascript(
          source: buildOfficialQueryPageFinalizePreparationScript(),
        );
      });
      _pagePreparationPending = false;
    }
  }

  Future<void> _handleDownloadStart(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    if (_disposed || _downloadInProgress) return;
    if (!_hasRecentExplicitGesture()) {
      _onDownloadError?.call('CSV_DOWNLOAD_EXPLICIT_TAP_REQUIRED');
      return;
    }

    final uri = Uri.tryParse(request.url.toString());
    if (uri == null) {
      _onDownloadError?.call('CSV_DOWNLOAD_URL_INVALID');
      return;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'data') {
      await _handleDataCsv(uri, request.suggestedFilename);
      return;
    }
    if (scheme == 'blob') {
      await _armBlobCsvTransfer(controller, uri, request.suggestedFilename);
      return;
    }
    if (scheme != 'https') {
      _onDownloadError?.call('CSV_DOWNLOAD_SCHEME_OTHER');
      return;
    }
    if (uri.userInfo.isNotEmpty || !isApprovedOfficialPortalHost(uri.host)) {
      _onDownloadError?.call('CSV_DOWNLOAD_HOST_NOT_APPROVED');
      return;
    }

    _downloadInProgress = true;
    try {
      final cookies = await _cookieManager.getCookies(
        url: request.url,
        webViewController: controller,
      );
      final transientCookieHeader = cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      final source = await _downloadService.downloadAndParse(
        EphemeralCsvDownloadRequest(
          url: uri,
          userAgent: request.userAgent,
          mimeType: request.mimeType,
          contentDisposition: request.contentDisposition,
          suggestedFilename: request.suggestedFilename,
          contentLength: request.contentLength,
          cookieHeader: transientCookieHeader,
        ),
      );
      if (_disposed) return;
      final onCsvReady = _onCsvReady;
      if (onCsvReady != null) await onCsvReady(source);
    } on EphemeralCsvDownloadException catch (error) {
      if (!_disposed) _onDownloadError?.call(error.code);
    } catch (_) {
      if (!_disposed) _onDownloadError?.call('CSV_DOWNLOAD_FAILED');
    } finally {
      _downloadInProgress = false;
    }
  }

  Future<void> _handleDataCsv(Uri uri, String? suggestedFilename) async {
    _downloadInProgress = true;
    try {
      final data = uri.data;
      if (data == null) {
        throw const EphemeralCsvDownloadException('CSV_DATA_URI_INVALID');
      }
      final bytes = Uint8List.fromList(data.contentAsBytes());
      final source = _pageGeneratedCsvParser.parse(
        bytes,
        fileName: suggestedFilename ?? 'official_page_export.csv',
      );
      final onCsvReady = _onCsvReady;
      if (!_disposed && onCsvReady != null) await onCsvReady(source);
    } on EphemeralCsvDownloadException catch (error) {
      if (!_disposed) _onDownloadError?.call(error.code);
    } catch (_) {
      if (!_disposed) _onDownloadError?.call('CSV_DATA_URI_INVALID');
    } finally {
      _downloadInProgress = false;
    }
  }

  Future<void> _armBlobCsvTransfer(
    InAppWebViewController controller,
    Uri blobUri,
    String? suggestedFilename,
  ) async {
    final current = await controller.getUrl();
    final currentUri = current == null ? null : Uri.tryParse(current.toString());
    if (!_isApprovedQueryRoute(currentUri)) {
      _onDownloadError?.call('CSV_BLOB_PAGE_NOT_APPROVED');
      return;
    }

    _downloadInProgress = true;
    _blobTransferArmed = true;
    _blobBytes = BytesBuilder(copy: false);
    _blobReceivedBytes = 0;
    _blobExpectedBytes = null;

    try {
      await controller.evaluateJavascript(
        source: buildOfficialPageGeneratedBlobReadScript(
          blobUri: blobUri,
          handlerName: _blobHandlerName,
          fileName: suggestedFilename ?? 'official_page_export.csv',
          maximumBytes: _maxGeneratedBytes,
        ),
      );
    } catch (_) {
      _resetBlobTransfer();
      if (!_disposed) _onDownloadError?.call('CSV_BLOB_READ_FAILED');
    }
  }

  Future<void> _handleBlobBridgeMessage(List<dynamic> arguments) async {
    if (!_blobTransferArmed || _disposed || arguments.isEmpty) return;
    final raw = arguments.first;
    if (raw is! Map) {
      _failBlobTransfer('CSV_BLOB_MESSAGE_INVALID');
      return;
    }
    final type = raw['type']?.toString();
    if (type == 'error') {
      final code = raw['code']?.toString();
      final safeCode = switch (code) {
        'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED' =>
          'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED',
        'CSV_BLOB_NOT_CAPTURED' => 'CSV_BLOB_NOT_CAPTURED',
        _ => 'CSV_BLOB_READ_FAILED',
      };
      _failBlobTransfer(safeCode);
      return;
    }
    if (type == 'start') {
      final size = (raw['size'] as num?)?.toInt();
      if (size == null || size < 0 || size > _maxGeneratedBytes) {
        _failBlobTransfer('CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED');
        return;
      }
      _blobExpectedBytes = size;
      return;
    }
    if (type == 'chunk') {
      final encoded = raw['base64']?.toString();
      if (encoded == null || encoded.isEmpty) {
        _failBlobTransfer('CSV_BLOB_MESSAGE_INVALID');
        return;
      }
      try {
        final chunk = base64Decode(encoded);
        _blobReceivedBytes += chunk.length;
        if (_blobReceivedBytes > _maxGeneratedBytes) {
          _failBlobTransfer('CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED');
          return;
        }
        _blobBytes?.add(chunk);
      } on FormatException {
        _failBlobTransfer('CSV_BLOB_MESSAGE_INVALID');
      }
      return;
    }
    if (type != 'end') return;

    final expected = _blobExpectedBytes;
    if (expected == null || expected != _blobReceivedBytes) {
      _failBlobTransfer('CSV_BLOB_SIZE_MISMATCH');
      return;
    }
    try {
      final bytes = _blobBytes?.takeBytes() ?? Uint8List(0);
      final source = _pageGeneratedCsvParser.parse(
        bytes,
        fileName: 'official_page_export.csv',
      );
      _resetBlobTransfer();
      final onCsvReady = _onCsvReady;
      if (!_disposed && onCsvReady != null) await onCsvReady(source);
    } on EphemeralCsvDownloadException catch (error) {
      _failBlobTransfer(error.code);
    } catch (_) {
      _failBlobTransfer('CSV_BLOB_READ_FAILED');
    }
  }

  void _failBlobTransfer(String code) {
    _resetBlobTransfer();
    if (!_disposed) _onDownloadError?.call(code);
  }

  void _resetBlobTransfer() {
    _blobTransferArmed = false;
    _blobBytes = null;
    _blobReceivedBytes = 0;
    _blobExpectedBytes = null;
    _downloadInProgress = false;
  }

  bool _hasRecentExplicitGesture() {
    final last = _lastPointerDownAt;
    return last != null &&
        DateTime.now().difference(last) <= _explicitGestureWindow;
  }

  Future<void> _applyCompatibilityScripts(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    try {
      final uri = url == null ? null : Uri.tryParse(url.toString());
      if (_isApprovedQueryRoute(uri)) {
        await controller.evaluateJavascript(
          source: buildOfficialQueryResultDesktopLayoutScript(),
        );
      }
      // No mobile viewport/fit-width injection: those scripts can force the
      // official portal back into its reduced responsive result structure.
    } catch (_) {
      // Visual compatibility remains best effort.
    }
  }

  bool _isApprovedQueryRoute(Uri? uri) {
    if (uri == null || uri.origin != approvedCloudInvoiceQueryOrigin) {
      return false;
    }
    final path = uri.path;
    return path == approvedCloudInvoiceQueryPath ||
        path == _queryRoutePrefix ||
        path.startsWith('$_queryRoutePrefix/');
  }

  bool _isAllowedNavigation(Uri uri) {
    if (uri.scheme.toLowerCase() == 'https') return true;
    return uri.scheme == 'about' && uri.path == 'blank';
  }

  void _validateNavigationUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(uri, 'initialUri', 'HTTPS required.');
    }
    if (uri.host.toLowerCase() != officialPortalPrimaryHost) {
      throw ArgumentError.value(uri, 'initialUri', 'Official host required.');
    }
  }

  @override
  Future<AuthenticatedSelectorCapabilityReport>
      probeSelectorCapabilities() async {
    final controller = _controller;
    if (_disposed) throw StateError('SESSION_RUNTIME_DISPOSED');
    if (controller == null) throw StateError('SESSION_NOT_OPEN');
    try {
      final rawResult = await controller.evaluateJavascript(
        source: buildOfficialQueryResultSelectorProbeScript(),
      );
      return _probeParser.parse(rawResult);
    } catch (_) {
      return _probeParser.parse(
        '{'
        '"schemaVersion":1,'
        '"probeSucceeded":false,'
        '"routeApproved":false,'
        '"capabilities":{},'
        '"availablePageSizes":[],'
        '"headers":{},'
        '"errorCode":"PROBE_EXECUTION_FAILED"'
        '}',
      );
    }
  }

  @override
  Future<OfficialQueryPagePreparationResult> prepareCurrentPageForExport() {
    return _prepareCurrentQueryPage(prepareExportSelection: true);
  }

  @override
  Future<OfficialQueryPagePreparationResult>
      prepareCurrentPageForOfficialDetail() {
    return _prepareCurrentQueryPage(prepareExportSelection: false);
  }

  Future<OfficialQueryPagePreparationResult> _prepareCurrentQueryPage({
    required bool prepareExportSelection,
  }) async {
    final controller = _controller;
    if (_disposed) throw StateError('SESSION_RUNTIME_DISPOSED');
    if (controller == null) throw StateError('SESSION_NOT_OPEN');
    try {
      final desktopGateRaw = await controller.evaluateJavascript(
        source: _buildDesktopResultStructureGateScript(),
      );
      if (!_desktopResultStructureReady(desktopGateRaw)) {
        return const OfficialQueryPagePreparationResult(
          code: 'DESKTOP_RESULT_LAYOUT_NOT_READY',
          routeApproved: true,
          pageSizeControlFound: false,
          pageSize100Requested: false,
          pageSizeApplyControlFound: false,
          pageSizeApplyTriggered: false,
          pageSizeAlreadyApplied: false,
          headerCheckboxFound: false,
          headerCheckboxSelected: false,
        );
      }

      final rawResult = await controller.evaluateJavascript(
        source: buildOfficialQueryPagePreparationScript(
          prepareExportSelection: prepareExportSelection,
        ),
      );
      final result = OfficialQueryPagePreparationResult.fromRaw(rawResult);
      if (prepareExportSelection && result.accepted) {
        _pagePreparationPending = true;
        if (result.pageSizeAlreadyApplied) {
          await controller.evaluateJavascript(
            source: buildOfficialQueryPageFinalizePreparationScript(),
          );
          _pagePreparationPending = false;
        }
      }
      return result;
    } catch (_) {
      return const OfficialQueryPagePreparationResult(
        code: 'PAGE_PREPARATION_EXECUTION_FAILED',
        routeApproved: false,
        pageSizeControlFound: false,
        pageSize100Requested: false,
        pageSizeApplyControlFound: false,
        pageSizeApplyTriggered: false,
        pageSizeAlreadyApplied: false,
        headerCheckboxFound: false,
        headerCheckboxSelected: false,
      );
    }
  }

  String _buildDesktopResultStructureGateScript() => r'''
(() => {
  const normalize = (value) => String(value || '')
    .replace(/[\s＊*：:]/g, '')
    .trim();
  const rendered = (element) => {
    if (!element) return false;
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      rect.width > 0 && rect.height > 0;
  };
  const requiredHeaders = [
    '載具自訂名稱',
    '發票號碼',
    '發票金額',
    '發票日期',
    '捐贈日期',
    '買方統編',
  ];
  const roots = Array.from(document.querySelectorAll(
    'table,[role="table"],[role="grid"],.table-responsive'
  )).filter(rendered);
  for (const root of roots) {
    const headers = Array.from(root.querySelectorAll(
      'th,[role="columnheader"]'
    )).filter(rendered).map((element) => normalize(element.textContent));
    if (!requiredHeaders.every((header) =>
      headers.some((candidate) => candidate.includes(header)))) {
      continue;
    }
    const headerCheckboxes = Array.from(root.querySelectorAll(
      'thead input[type="checkbox"],thead [role="checkbox"],' +
      '[role="columnheader"] input[type="checkbox"],' +
      '[role="columnheader"] [role="checkbox"]'
    )).filter(rendered);
    const rows = Array.from(root.querySelectorAll(
      'tbody tr,[role="row"]'
    )).filter((row) => rendered(row) && !row.closest('thead'));
    const rowsWithTwoRoles = rows.filter((row) =>
      Array.from(row.querySelectorAll(
        'input[type="checkbox"],[role="checkbox"]'
      )).filter(rendered).length >= 2
    ).length;
    if (headerCheckboxes.length >= 2 && rowsWithTwoRoles > 0) {
      return JSON.stringify({
        code: 'DESKTOP_RESULT_LAYOUT_READY',
        ready: true,
        headerCheckboxCount: headerCheckboxes.length,
        rowsWithTwoRoles,
      });
    }
  }
  return JSON.stringify({
    code: 'DESKTOP_RESULT_LAYOUT_NOT_READY',
    ready: false,
  });
})()
''';

  bool _desktopResultStructureReady(Object? raw) {
    Object? decoded = raw;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return false;
      }
    }
    return decoded is Map &&
        decoded['ready'] == true &&
        decoded['code'] == 'DESKTOP_RESULT_LAYOUT_READY';
  }

  @override
  Future<OfficialInvoiceDetailTargetReport> inspectOfficialDetailTargets() async {
    final controller = _controller;
    if (_disposed) throw StateError('SESSION_RUNTIME_DISPOSED');
    if (controller == null) throw StateError('SESSION_NOT_OPEN');
    final current = await controller.getUrl();
    final uri = current == null ? null : Uri.tryParse(current.toString());
    if (uri == null ||
        !isApprovedOfficialPortalHttpsUri(uri) ||
        !_isApprovedQueryRoute(uri)) {
      return const OfficialInvoiceDetailTargetReport(
        routeApproved: false,
        selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
        targets: <OfficialInvoiceDetailTarget>[],
        errorCode: 'DETAIL_ROUTE_REJECTED',
      );
    }
    try {
      final raw = await controller.evaluateJavascript(
        source: buildOfficialInvoiceDetailTargetInspectionScript(),
      );
      return OfficialInvoiceDetailTargetReport.fromRaw(raw);
    } catch (_) {
      return const OfficialInvoiceDetailTargetReport(
        routeApproved: true,
        selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
        targets: <OfficialInvoiceDetailTarget>[],
        errorCode: 'DETAIL_TARGET_INSPECTION_FAILED',
      );
    }
  }

  @override
  Future<OfficialInvoiceDetailBatchResult> enrichOfficialInvoiceDetails({
    required OfficialInvoiceDetailSelectionScope scope,
    String? singleInvoiceNumber,
    required void Function(OfficialInvoiceDetailProgress progress) onProgress,
  }) async {
    final controller = _controller;
    if (_disposed) throw StateError('SESSION_RUNTIME_DISPOSED');
    if (controller == null) throw StateError('SESSION_NOT_OPEN');
    if (_detailCompleter != null) {
      throw StateError('DETAIL_BATCH_ALREADY_ACTIVE');
    }
    final current = await controller.getUrl();
    final uri = current == null ? null : Uri.tryParse(current.toString());
    if (uri == null ||
        !isApprovedOfficialPortalHttpsUri(uri) ||
        !_isApprovedQueryRoute(uri)) {
      throw StateError('DETAIL_ROUTE_REJECTED');
    }

    final completer = Completer<OfficialInvoiceDetailBatchResult>();
    _detailCompleter = completer;
    _detailResults = <OfficialInvoiceDetailEnrichment>[];
    _detailProgress = onProgress;
    _detailRequestedCount = 0;
    _detailTraces = <OfficialInvoiceDetailTraceItem>[];
    _detailActiveInvoiceNumber = null;
    _detailActiveOrdinal = null;

    try {
      await controller.evaluateJavascript(
        source: buildOfficialInvoiceDetailEnrichmentTraceScript(
          scope: scope,
          handlerName: _detailHandlerName,
          singleInvoiceNumber: singleInvoiceNumber,
        ),
      );
    } catch (_) {
      _completeOfficialDetailBatch(
        requestedCount: 0,
        cancelled: false,
        errorCode: 'DETAIL_SCRIPT_START_FAILED',
      );
    }

    try {
      return await completer.future.timeout(_detailBatchHardTimeout);
    } on TimeoutException {
      await _signalOfficialDetailCancellation();
      _completeOfficialDetailBatch(
        requestedCount: _detailRequestedCount,
        cancelled: true,
        errorCode: 'DETAIL_BATCH_TIMEOUT',
      );
      return completer.future;
    }
  }

  Future<void> _signalOfficialDetailCancellation() async {
    final controller = _controller;
    if (controller == null) return;
    await _attemptBestEffort(() async {
      await controller.evaluateJavascript(
        source: buildOfficialInvoiceDetailCancellationScript(),
      );
    });
  }

  @override
  Future<void> cancelOfficialInvoiceDetailEnrichment() async {
    final completer = _detailCompleter;
    if (completer == null || completer.isCompleted) return;
    await _signalOfficialDetailCancellation();
    _completeOfficialDetailBatch(
      requestedCount: _detailRequestedCount,
      cancelled: true,
      errorCode: 'DETAIL_CANCELLED',
    );
  }

  void _handleOfficialDetailBridgeMessage(List<dynamic> arguments) {
    if (_disposed || _detailCompleter == null || arguments.isEmpty) return;
    final raw = arguments.first;
    if (raw is! Map) return;
    final payload = <String, Object?>{
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    };
    final type = payload['type']?.toString();
    if (type == 'started') {
      _detailRequestedCount = (payload['total'] as num?)?.toInt() ?? 0;
      final rawTargets = payload['targets'];
      _detailTraces = rawTargets is List
          ? rawTargets.indexed.map((entry) {
              final rawTarget = entry.$2;
              final map = rawTarget is Map
                  ? rawTarget
                  : const <Object?, Object?>{};
              return OfficialInvoiceDetailTraceItem(
                invoiceNumber: map['invoiceNumber']?.toString() ?? '',
                ordinal: (map['ordinal'] as num?)?.toInt() ?? entry.$1 + 1,
                status: OfficialInvoiceDetailTraceStatus.pending,
              );
            }).where((item) => item.invoiceNumber.isNotEmpty).toList()
          : <OfficialInvoiceDetailTraceItem>[];
      return;
    }
    if (type == 'progress') {
      final progress = OfficialInvoiceDetailProgress(
        current: (payload['current'] as num?)?.toInt() ?? 0,
        total: (payload['total'] as num?)?.toInt() ?? _detailRequestedCount,
        invoiceNumber: payload['invoiceNumber']?.toString() ?? '',
        message: payload['message']?.toString() ?? '',
      );
      _detailActiveInvoiceNumber = progress.invoiceNumber;
      _detailActiveOrdinal = progress.current;
      _updateDetailTrace(
        progress.invoiceNumber,
        ordinal: progress.current,
        status: OfficialInvoiceDetailTraceStatus.running,
        startedAt: DateTime.now().toUtc(),
      );
      _detailProgress?.call(progress);
      return;
    }
    if (type == 'result') {
      final result = payload['result'];
      if (result is Map) {
        final resultOrdinal = (payload['ordinal'] as num?)?.toInt();
        final enrichment =
            OfficialInvoiceDetailEnrichment.fromJson(<String, Object?>{
          for (final entry in result.entries)
            entry.key.toString(): entry.value,
        });
        _detailResults.add(enrichment);
        final invoiceNumber = enrichment.invoiceNumber.isNotEmpty
            ? enrichment.invoiceNumber
            : enrichment.requestedInvoiceNumber;
        _updateDetailTrace(
          invoiceNumber,
          ordinal: resultOrdinal,
          status: enrichment.success
              ? OfficialInvoiceDetailTraceStatus.success
              : _isTechnicalDetailFailure(enrichment.errorCode)
                  ? OfficialInvoiceDetailTraceStatus.failed
                  : OfficialInvoiceDetailTraceStatus.review,
          completedAt: DateTime.now().toUtc(),
          reasonCode: enrichment.errorCode,
        );
        final matchesActiveOrdinal = resultOrdinal != null &&
            _detailActiveOrdinal == resultOrdinal;
        if (matchesActiveOrdinal ||
            (resultOrdinal == null &&
                _detailActiveInvoiceNumber == invoiceNumber)) {
          _detailActiveInvoiceNumber = null;
          _detailActiveOrdinal = null;
        }
      }
      return;
    }
    if (type == 'complete') {
      _completeOfficialDetailBatch(
        requestedCount: (payload['requestedCount'] as num?)?.toInt() ??
            _detailRequestedCount,
        cancelled: payload['cancelled'] == true,
        errorCode: payload['errorCode']?.toString(),
      );
    }
  }

  void _updateDetailTrace(
    String invoiceNumber, {
    int? ordinal,
    required OfficialInvoiceDetailTraceStatus status,
    DateTime? startedAt,
    DateTime? completedAt,
    String? reasonCode,
  }) {
    final normalized = invoiceNumber.trim().toUpperCase();
    var index = ordinal == null
        ? -1
        : _detailTraces.indexWhere((item) => item.ordinal == ordinal);
    if (index < 0) {
      index = _detailTraces.indexWhere(
        (item) => item.invoiceNumber.trim().toUpperCase() == normalized,
      );
    }
    if (index < 0) return;
    final current = _detailTraces[index];
    _detailTraces[index] = OfficialInvoiceDetailTraceItem(
      invoiceNumber: current.invoiceNumber,
      ordinal: current.ordinal,
      status: status,
      startedAt: current.startedAt ?? startedAt,
      completedAt: completedAt ?? current.completedAt,
      reasonCode: reasonCode ?? current.reasonCode,
    );
  }

  bool _isTechnicalDetailFailure(String? code) {
    return const <String>{
      'DETAIL_NO_DIALOG',
      'DETAIL_RENDER_TIMEOUT',
      'DETAIL_LINK_NOT_FOUND',
      'DETAIL_LINK_CLICK_FAILED',
      'DETAIL_SCRIPT_START_FAILED',
      'DETAIL_BATCH_FAILED',
    }.contains(code);
  }

  List<OfficialInvoiceDetailTraceItem> _finalizeDetailTraces({
    required bool cancelled,
    required String? errorCode,
  }) {
    final completedAt = DateTime.now().toUtc();
    return _detailTraces.map((trace) {
      if (trace.isTerminal) return trace;
      final isActive = _detailActiveOrdinal != null
          ? trace.ordinal == _detailActiveOrdinal
          : _detailActiveInvoiceNumber != null &&
              trace.invoiceNumber.trim().toUpperCase() ==
                  _detailActiveInvoiceNumber!.trim().toUpperCase();
      final wasRunning =
          trace.status == OfficialInvoiceDetailTraceStatus.running;
      final status = cancelled
          ? isActive || wasRunning
              ? OfficialInvoiceDetailTraceStatus.cancelledActive
              : OfficialInvoiceDetailTraceStatus.notStartedAfterCancel
          : OfficialInvoiceDetailTraceStatus.missingTerminalResult;
      final reason = cancelled && errorCode == 'DETAIL_CANCELLED'
          ? isActive || wasRunning
              ? 'DETAIL_CANCELLED_ACTIVE'
              : 'DETAIL_NOT_STARTED_AFTER_CANCEL'
          : errorCode ?? 'DETAIL_MISSING_TERMINAL_RESULT';
      return OfficialInvoiceDetailTraceItem(
        invoiceNumber: trace.invoiceNumber,
        ordinal: trace.ordinal,
        status: status,
        startedAt: trace.startedAt,
        completedAt: completedAt,
        reasonCode: reason,
      );
    }).toList(growable: false);
  }

  void _completeOfficialDetailBatch({
    required int requestedCount,
    required bool cancelled,
    String? errorCode,
  }) {
    final completer = _detailCompleter;
    if (completer == null || completer.isCompleted) return;
    final result = OfficialInvoiceDetailBatchResult(
      requestedCount: requestedCount,
      results: List<OfficialInvoiceDetailEnrichment>.unmodifiable(
        _detailResults,
      ),
      cancelled: cancelled,
      traces: List<OfficialInvoiceDetailTraceItem>.unmodifiable(
        _finalizeDetailTraces(cancelled: cancelled, errorCode: errorCode),
      ),
      errorCode: errorCode,
    );
    _detailCompleter = null;
    _detailResults = <OfficialInvoiceDetailEnrichment>[];
    _detailProgress = null;
    _detailRequestedCount = 0;
    _detailTraces = <OfficialInvoiceDetailTraceItem>[];
    _detailActiveInvoiceNumber = null;
    _detailActiveOrdinal = null;
    completer.complete(result);
  }

  @override
  Future<void> clearSession() async {
    await cancelOfficialInvoiceDetailEnrichment();
    final failures = <String>[];
    _pagePreparationPending = false;
    _resetBlobTransfer();
    await _attempt(failures, 'download_cancel', _downloadService.cancel);

    final controller = _controller;
    if (controller != null) {
      await _attemptBestEffort(() async {
        await controller.evaluateJavascript(
          source: 'window.sessionStorage.clear(); '
              'window.localStorage.clear();',
        );
      });
      await _attemptBestEffort(controller.stopLoading);
      await _attempt(failures, 'cache', () async {
        await InAppWebViewController.clearAllCache();
      });
    }

    await _attempt(failures, 'cookies', () async {
      await _cookieManager.deleteAllCookies();
    });
    await _attempt(failures, 'web_storage', () async {
      await _webStorageManager.deleteAllData();
    });
    await _attempt(
      failures,
      'temporary_files',
      _downloadService.cleanupStaleFiles,
    );

    _controller = null;
    _initialUri = null;
    _lastPointerDownAt = null;

    if (failures.isNotEmpty) {
      throw StateError(
        'WEBVIEW_SESSION_CLEANUP_FAILED:${failures.join(',')}',
      );
    }
  }

  Future<void> _clearBeforeOpen() async {
    final failures = <String>[];
    await _attempt(
      failures,
      'preopen_temporary_files',
      _downloadService.cleanupStaleFiles,
    );
    await _attempt(failures, 'preopen_cache', () async {
      await InAppWebViewController.clearAllCache();
    });
    await _attempt(failures, 'preopen_web_storage', () async {
      await _webStorageManager.deleteAllData();
    });
    await _attempt(failures, 'preopen_cookies', () async {
      await _cookieManager.deleteAllCookies();
    });
    if (failures.isNotEmpty) {
      throw StateError(
        'WEBVIEW_PREOPEN_CLEANUP_FAILED:${failures.join(',')}',
      );
    }
  }

  Future<void> _attempt(
    List<String> failures,
    String step,
    Future<void> Function() action,
  ) async {
    try {
      await action().timeout(_cleanupStepTimeout);
    } on TimeoutException {
      failures.add('$step:timeout');
    } catch (_) {
      failures.add(step);
    }
  }

  Future<void> _attemptBestEffort(Future<void> Function() action) async {
    try {
      await action().timeout(_cleanupStepTimeout);
    } catch (_) {
      // Persistent cache/cookie/web-storage cleanup remains authoritative.
    }
  }

  @override
  void dispose() {
    _completeOfficialDetailBatch(
      requestedCount: _detailRequestedCount,
      cancelled: true,
      errorCode: 'DETAIL_SESSION_DISPOSED',
    );
    _pagePreparationPending = false;
    _resetBlobTransfer();
    unawaited(_downloadService.cancel());
    _controller?.dispose();
    _controller = null;
    _initialUri = null;
    _lastPointerDownAt = null;
    _disposed = true;
  }
}

// Retired mobile layout hooks kept only for contract traceability: buildOfficialMobileViewportCompatibilityScript buildOfficialMobileFitWidthScript
