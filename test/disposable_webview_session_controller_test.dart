import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/disposable_webview_session.dart';

void main() {
  test('requires explicit consent before session start', () async {
    final runtime = _FakeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );

    expect(controller.phase, DisposableWebViewSessionPhase.consent);
    expect(controller.canStart, isFalse);

    await expectLater(
      controller.start(Uri.parse('https://example.test')),
      throwsA(isA<StateError>()),
    );
    expect(runtime.openCount, 0);

    controller.dispose();
  });

  test('rejects non-HTTPS session targets', () async {
    final runtime = _FakeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);

    await expectLater(
      controller.start(Uri.parse('http://example.test')),
      throwsA(isA<ArgumentError>()),
    );
    expect(runtime.openCount, 0);
    expect(controller.phase, DisposableWebViewSessionPhase.consent);

    controller.dispose();
  });

  test('finish clears and disposes the active session', () async {
    final runtime = _FakeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);

    await controller.start(Uri.parse('https://example.test'));
    expect(controller.phase, DisposableWebViewSessionPhase.active);
    expect(runtime.openCount, 1);

    await controller.finish();

    expect(runtime.clearCount, 1);
    expect(runtime.disposeCount, 1);
    expect(controller.phase, DisposableWebViewSessionPhase.completed);
    expect(controller.consentAccepted, isFalse);
    expect(controller.hasRuntime, isFalse);

    controller.resetAfterCompletion();
    expect(controller.phase, DisposableWebViewSessionPhase.consent);
    expect(controller.canStart, isFalse);

    controller.dispose();
  });

  test('cancel uses the same cleanup gate as finish', () async {
    final runtime = _FakeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);

    await controller.start(Uri.parse('https://example.test'));
    await controller.cancel();

    expect(runtime.clearCount, 1);
    expect(runtime.disposeCount, 1);
    expect(controller.phase, DisposableWebViewSessionPhase.completed);

    controller.dispose();
  });

  test('cleanup failure blocks every later session', () async {
    final runtime = _FakeRuntime(failClear: true);
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);

    await controller.start(Uri.parse('https://example.test'));
    await controller.finish();

    expect(controller.phase, DisposableWebViewSessionPhase.blocked);
    expect(controller.isBlocked, isTrue);
    expect(controller.errorMessage, contains('SESSION_CLEANUP_FAILED'));

    controller.setConsentAccepted(true);
    expect(controller.consentAccepted, isFalse);
    await expectLater(
      controller.start(Uri.parse('https://example.test')),
      throwsA(isA<StateError>()),
    );

    controller.dispose();
  });

  test('cleanup timeout blocks instead of hanging indefinitely', () async {
    final runtime = _FakeRuntime(hangClear: true);
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
      cleanupTimeout: const Duration(milliseconds: 20),
    );
    controller.setConsentAccepted(true);

    await controller.start(Uri.parse('https://example.test'));
    await controller.finish();

    expect(runtime.clearCount, 1);
    expect(runtime.disposeCount, 1);
    expect(controller.phase, DisposableWebViewSessionPhase.blocked);
    expect(controller.errorMessage, contains('SESSION_CLEANUP_TIMEOUT'));
    expect(controller.hasRuntime, isFalse);

    controller.dispose();
  });

  test('start failure can retry only after successful cleanup', () async {
    final firstRuntime = _FakeRuntime(failOpen: true);
    final secondRuntime = _FakeRuntime();
    var runtimeIndex = 0;
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () =>
          runtimeIndex++ == 0 ? firstRuntime : secondRuntime,
    );
    controller.setConsentAccepted(true);

    await controller.start(Uri.parse('https://example.test'));

    expect(firstRuntime.clearCount, 1);
    expect(firstRuntime.disposeCount, 1);
    expect(controller.phase, DisposableWebViewSessionPhase.failed);

    controller.resetAfterStartFailure();
    expect(controller.phase, DisposableWebViewSessionPhase.consent);
    expect(controller.consentAccepted, isFalse);

    controller.setConsentAccepted(true);
    await controller.start(Uri.parse('https://example.test'));
    expect(controller.phase, DisposableWebViewSessionPhase.active);
    expect(secondRuntime.openCount, 1);

    await controller.cancel();
    controller.dispose();
  });

  test('start plus cleanup failure enters blocked state', () async {
    final runtime = _FakeRuntime(failOpen: true, failClear: true);
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );
    controller.setConsentAccepted(true);

    await controller.start(Uri.parse('https://example.test'));

    expect(controller.phase, DisposableWebViewSessionPhase.blocked);
    expect(
      controller.errorMessage,
      contains('SESSION_START_AND_CLEANUP_FAILED'),
    );

    controller.dispose();
  });
}

class _FakeRuntime implements DisposableWebViewSessionRuntime {
  _FakeRuntime({
    this.failOpen = false,
    this.failClear = false,
    this.hangClear = false,
  });

  final bool failOpen;
  final bool failClear;
  final bool hangClear;

  int openCount = 0;
  int clearCount = 0;
  int disposeCount = 0;

  @override
  Future<void> open(Uri initialUri) async {
    openCount += 1;
    if (failOpen) throw StateError('open failed');
  }

  @override
  Widget buildView() => const SizedBox(key: Key('fake_webview'));

  @override
  Future<void> clearSession() async {
    clearCount += 1;
    if (failClear) throw StateError('clear failed');
    if (hangClear) await Completer<void>().future;
  }

  @override
  void dispose() {
    disposeCount += 1;
  }
}
