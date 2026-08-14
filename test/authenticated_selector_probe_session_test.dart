import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/authenticated_selector_capability_probe.dart';
import 'package:my_finance_app/features/invoice/lab/disposable_webview_session.dart';

void main() {
  test('probe is unavailable before the disposable session is active', () async {
    final runtime = _ProbeRuntime(report: _successfulReport());
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );

    expect(controller.canProbeAuthenticatedSelectors, isFalse);
    await expectLater(
      controller.probeAuthenticatedSelectorCapabilities(),
      throwsA(isA<StateError>()),
    );

    controller.dispose();
  });

  test('active session returns an in-memory capability report', () async {
    final expectedReport = _successfulReport();
    final runtime = _ProbeRuntime(report: expectedReport);
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://www.einvoice.nat.gov.tw'));

    expect(controller.canProbeAuthenticatedSelectors, isTrue);
    final report =
        await controller.probeAuthenticatedSelectorCapabilities();

    expect(report, same(expectedReport));
    expect(runtime.probeCount, 1);

    await controller.finish();
    expect(controller.canProbeAuthenticatedSelectors, isFalse);
    controller.dispose();
  });

  test('hanging selector probe fails closed within the configured timeout',
      () async {
    final runtime = _HangingProbeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
      selectorProbeTimeout: const Duration(milliseconds: 20),
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://www.einvoice.nat.gov.tw'));

    await expectLater(
      controller.probeAuthenticatedSelectorCapabilities(),
      throwsA(isA<TimeoutException>()),
    );

    expect(controller.phase, DisposableWebViewSessionPhase.active);
    await controller.finish();
    controller.dispose();
  });

  test('active runtime without probe support is rejected', () async {
    final runtime = _SessionOnlyRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://www.einvoice.nat.gov.tw'));

    expect(controller.canProbeAuthenticatedSelectors, isFalse);
    await expectLater(
      controller.probeAuthenticatedSelectorCapabilities(),
      throwsA(isA<StateError>()),
    );

    await controller.cancel();
    controller.dispose();
  });
}

AuthenticatedSelectorCapabilityReport _successfulReport() {
  return AuthenticatedSelectorCapabilityReport(
    probeSucceeded: true,
    routeApproved: true,
    matches: <AuthenticatedSelectorCapability,
        AuthenticatedSelectorCapabilityMatch>{
      for (final capability in AuthenticatedSelectorCapability.values)
        capability: AuthenticatedSelectorCapabilityMatch(
          capability: capability,
          matchCount: 1,
          maximumMatches: 1,
        ),
    },
    availablePageSizes: const <int>[10, 20, 50, 100],
    headerMatches: <String, bool>{
      for (final header in expectedOfficialResultHeaders) header: true,
    },
    issues: const <AuthenticatedSelectorProbeIssue>[],
  );
}

class _ProbeRuntime
    implements
        DisposableWebViewSessionRuntime,
        AuthenticatedSelectorCapabilityProbeRuntime {
  _ProbeRuntime({required this.report});

  final AuthenticatedSelectorCapabilityReport report;
  int probeCount = 0;

  @override
  Future<void> open(Uri initialUri) async {}

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<AuthenticatedSelectorCapabilityReport>
      probeSelectorCapabilities() async {
    probeCount += 1;
    return report;
  }

  @override
  Future<void> clearSession() async {}

  @override
  void dispose() {}
}

class _HangingProbeRuntime
    implements
        DisposableWebViewSessionRuntime,
        AuthenticatedSelectorCapabilityProbeRuntime {
  final Completer<AuthenticatedSelectorCapabilityReport> _completer =
      Completer<AuthenticatedSelectorCapabilityReport>();

  @override
  Future<void> open(Uri initialUri) async {}

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<AuthenticatedSelectorCapabilityReport>
      probeSelectorCapabilities() => _completer.future;

  @override
  Future<void> clearSession() async {}

  @override
  void dispose() {}
}

class _SessionOnlyRuntime implements DisposableWebViewSessionRuntime {
  @override
  Future<void> open(Uri initialUri) async {}

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<void> clearSession() async {}

  @override
  void dispose() {}
}
