import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/disposable_webview_session.dart';
import 'package:my_finance_app/features/invoice/lab/disposable_webview_session_shell.dart';

void main() {
  testWidgets('start remains disabled until explicit consent', (tester) async {
    final runtime = _FakeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DisposableWebViewSessionShell(
          initialUri: Uri.parse('https://example.test'),
          controller: controller,
        ),
      ),
    );

    final startButton = tester.widget<FilledButton>(
      find.byKey(DisposableWebViewSessionShell.startButtonKey),
    );
    expect(startButton.onPressed, isNull);

    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.consentCheckboxKey),
    );
    await tester.pump();

    final enabledStartButton = tester.widget<FilledButton>(
      find.byKey(DisposableWebViewSessionShell.startButtonKey),
    );
    expect(enabledStartButton.onPressed, isNotNull);

    controller.dispose();
  });

  testWidgets('finish clears session and requires new consent', (tester) async {
    final runtime = _FakeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DisposableWebViewSessionShell(
          initialUri: Uri.parse('https://example.test'),
          controller: controller,
        ),
      ),
    );

    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.consentCheckboxKey),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.startButtonKey),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fake_webview')), findsOneWidget);
    expect(
      find.byKey(DisposableWebViewSessionShell.finishButtonKey),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.finishButtonKey),
    );
    await tester.pumpAndSettle();

    expect(runtime.clearCount, 1);
    expect(runtime.disposeCount, 1);
    expect(find.text('工作階段已清除'), findsOneWidget);

    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.resetButtonKey),
    );
    await tester.pump();

    expect(find.text('一次性登入工作階段'), findsOneWidget);
    final startButton = tester.widget<FilledButton>(
      find.byKey(DisposableWebViewSessionShell.startButtonKey),
    );
    expect(startButton.onPressed, isNull);

    controller.dispose();
  });

  testWidgets('cancel also clears the session', (tester) async {
    final runtime = _FakeRuntime();
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DisposableWebViewSessionShell(
          initialUri: Uri.parse('https://example.test'),
          controller: controller,
        ),
      ),
    );

    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.consentCheckboxKey),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.startButtonKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.cancelButtonKey),
    );
    await tester.pumpAndSettle();

    expect(runtime.clearCount, 1);
    expect(find.text('工作階段已清除'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('cleanup failure shows a permanent blocked state', (tester) async {
    final runtime = _FakeRuntime(failClear: true);
    final controller = DisposableWebViewSessionController(
      runtimeFactory: () => runtime,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DisposableWebViewSessionShell(
          initialUri: Uri.parse('https://example.test'),
          controller: controller,
        ),
      ),
    );

    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.consentCheckboxKey),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.startButtonKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(DisposableWebViewSessionShell.finishButtonKey),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(DisposableWebViewSessionShell.blockedPanelKey),
      findsOneWidget,
    );
    expect(find.text('清理失敗，已封鎖後續登入'), findsOneWidget);
    expect(
      find.byKey(DisposableWebViewSessionShell.resetButtonKey),
      findsNothing,
    );

    controller.dispose();
  });
}

class _FakeRuntime implements DisposableWebViewSessionRuntime {
  _FakeRuntime({this.failClear = false});

  final bool failClear;
  int clearCount = 0;
  int disposeCount = 0;

  @override
  Future<void> open(Uri initialUri) async {}

  @override
  Widget buildView() => const SizedBox(key: Key('fake_webview'));

  @override
  Future<void> clearSession() async {
    clearCount += 1;
    if (failClear) throw StateError('clear failed');
  }

  @override
  void dispose() {
    disposeCount += 1;
  }
}
