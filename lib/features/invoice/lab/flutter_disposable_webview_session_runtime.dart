import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'authenticated_selector_capability_probe.dart';
import 'disposable_webview_session.dart';

class FlutterDisposableWebViewSessionRuntime
    implements
        DisposableWebViewSessionRuntime,
        AuthenticatedSelectorCapabilityProbeRuntime {
  FlutterDisposableWebViewSessionRuntime({
    WebViewCookieManager? cookieManager,
    AuthenticatedSelectorCapabilityReportParser? probeParser,
  })  : _cookieManager = cookieManager ?? WebViewCookieManager(),
        _probeParser =
            probeParser ?? const AuthenticatedSelectorCapabilityReportParser();

  final WebViewCookieManager _cookieManager;
  final AuthenticatedSelectorCapabilityReportParser _probeParser;

  WebViewController? _controller;
  bool _disposed = false;

  @override
  Future<void> open(Uri initialUri) async {
    if (_disposed) throw StateError('SESSION_RUNTIME_DISPOSED');
    if (_controller != null) throw StateError('SESSION_ALREADY_OPEN');
    if (initialUri.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(
        initialUri,
        'initialUri',
        'Only HTTPS navigation is allowed.',
      );
    }

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme.toLowerCase() == 'https') {
            return NavigationDecision.navigate;
          }
          if (uri.scheme == 'about' && uri.path == 'blank') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ),
    );

    await _clearBeforeOpen(controller);
    _controller = controller;
    await controller.loadRequest(initialUri);
  }

  @override
  Widget buildView() {
    final controller = _controller;
    if (controller == null) {
      throw StateError('SESSION_NOT_OPEN');
    }
    return WebViewWidget(controller: controller);
  }

  @override
  Future<AuthenticatedSelectorCapabilityReport>
      probeSelectorCapabilities() async {
    if (_disposed) throw StateError('SESSION_RUNTIME_DISPOSED');
    final controller = _controller;
    if (controller == null) throw StateError('SESSION_NOT_OPEN');

    try {
      final rawResult = await controller.runJavaScriptReturningResult(
        buildAuthenticatedSelectorCapabilityProbeScript(),
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
  Future<void> clearSession() async {
    final controller = _controller;
    if (controller == null) return;

    final failures = <String>[];

    await _attempt(
      failures,
      'session_storage',
      () async {
        await controller.runJavaScript(
          'window.sessionStorage.clear(); window.localStorage.clear();',
        );
      },
    );
    await _attempt(
      failures,
      'local_storage',
      () async {
        await controller.clearLocalStorage();
      },
    );
    await _attempt(
      failures,
      'cache',
      () async {
        await controller.clearCache();
      },
    );
    await _attempt(
      failures,
      'cookies',
      () async {
        await _cookieManager.clearCookies();
      },
    );
    await _attempt(
      failures,
      'blank_page',
      () async {
        await controller.loadHtmlString(
          '<!doctype html><html><body></body></html>',
          baseUrl: 'about:blank',
        );
      },
    );

    _controller = null;

    if (failures.isNotEmpty) {
      throw StateError(
        'WEBVIEW_SESSION_CLEANUP_FAILED:${failures.join(',')}',
      );
    }
  }

  Future<void> _clearBeforeOpen(WebViewController controller) async {
    final failures = <String>[];
    await _attempt(
      failures,
      'preopen_local_storage',
      () async {
        await controller.clearLocalStorage();
      },
    );
    await _attempt(
      failures,
      'preopen_cache',
      () async {
        await controller.clearCache();
      },
    );
    await _attempt(
      failures,
      'preopen_cookies',
      () async {
        await _cookieManager.clearCookies();
      },
    );
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
      await action();
    } catch (_) {
      failures.add(step);
    }
  }

  @override
  void dispose() {
    _controller = null;
    _disposed = true;
  }
}
