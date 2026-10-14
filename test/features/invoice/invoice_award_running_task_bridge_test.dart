import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_running_task_bridge.dart';

void main() {
  InvoiceAwardRunningTaskSnapshot progress(String period, String stage) =>
      InvoiceAwardRunningTaskSnapshot(
        periodId: period,
        status: '一般獎已驗證',
        cloudStatus: stage,
        scanStatus: '一般獎中獎 1 筆；雲端尚未完成',
      );

  test('route reentry subscribes to the same running progress', () {
    final bridge = InvoiceAwardRunningTaskBridge();
    final seen = <String>[];
    expect(bridge.begin('115-07-08'), isTrue);
    final generation = bridge.generation;
    void oldRoute() => seen.add('old:${bridge.snapshotFor('115-07-08')?.cloudStatus}');
    bridge.addListener(oldRoute);
    bridge.publish(generation, progress('115-07-08', 'PLATFORM_SOURCE_SHA256'));
    bridge.removeListener(oldRoute); // Navigator pop / disposed State
    void newRoute() => seen.add('new:${bridge.snapshotFor('115-07-08')?.cloudStatus}');
    bridge.addListener(newRoute); // Navigator push / fresh State
    expect(bridge.activeFor('115-07-08'), isTrue);
    expect(bridge.snapshotFor('115-07-08')!.cloudStatus,
        'PLATFORM_SOURCE_SHA256');
    bridge.publish(generation, progress('115-07-08', 'PLATFORM_RENDERER_OPEN_WAIT'));
    expect(seen, <String>[
      'old:PLATFORM_SOURCE_SHA256',
      'new:PLATFORM_RENDERER_OPEN_WAIT',
    ]);
    bridge.finish(generation, '115-07-08');
    expect(bridge.active, isFalse);
    expect(bridge.snapshotFor('115-07-08')!.cloudStatus,
        'PLATFORM_RENDERER_OPEN_WAIT');
    bridge.dispose();
  });

  test('single flight blocks a second authorized task', () {
    final bridge = InvoiceAwardRunningTaskBridge();
    expect(bridge.begin('115-07-08'), isTrue);
    expect(bridge.begin('115-05-06'), isFalse);
    expect(bridge.periodId, '115-07-08');
    bridge.dispose();
  });

  test('period mismatches and stale generation cannot override result', () {
    final bridge = InvoiceAwardRunningTaskBridge();
    expect(bridge.begin('115-07-08'), isTrue);
    final first = bridge.generation;
    bridge.publish(first, progress('115-05-06', 'FORGED_PERIOD'));
    expect(bridge.snapshotFor('115-07-08'), isNull);
    bridge.publish(first, progress('115-07-08', 'REAL_STAGE'));
    bridge.finish(first, '115-05-06'); // wrong terminal identity
    expect(bridge.active, isTrue);
    bridge.finish(first, '115-07-08');
    expect(bridge.begin('115-05-06'), isTrue);
    bridge.publish(first, progress('115-05-06', 'STALE_RESULT'));
    expect(bridge.snapshotFor('115-05-06'), isNull);
    expect(bridge.snapshotFor('115-07-08'), isNull);
    bridge.dispose();
  });

  test('new Android process has no trustworthy running task', () {
    final previousProcess = InvoiceAwardRunningTaskBridge();
    expect(previousProcess.begin('115-07-08'), isTrue);
    previousProcess.publish(
      previousProcess.generation,
      progress('115-07-08', 'PLATFORM_RENDERER_OPEN_WAIT'),
    );
    final restartedProcess = InvoiceAwardRunningTaskBridge();
    expect(restartedProcess.active, isFalse);
    expect(restartedProcess.snapshotFor('115-07-08'), isNull);
    previousProcess.dispose();
    restartedProcess.dispose();
  });
}
