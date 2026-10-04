import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance_app/features/invoice/invoice_award_runtime_scheduler.dart';

void main() {
  late _FakePlatform platform;
  late InvoiceAwardRuntimeScheduler scheduler;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    platform = _FakePlatform();
    scheduler = InvoiceAwardRuntimeScheduler(
      repository: InvoiceAwardRuntimeStateRepository(preferences),
      platform: platform,
    );
  });

  test('opt-out cancels native wake and schedules no network-capable work', () async {
    await scheduler.setConsent(false);
    final result = await scheduler.reconcile(
      nowLocal: DateTime(2026, 9, 25, 14),
      periodId: '115-07-08',
    );
    expect(result.consent, isFalse);
    expect(result.nextTargetLocal, isNull);
    expect(platform.cancelCount, greaterThanOrEqualTo(1));
    expect(platform.scheduled, isEmpty);
  });

  test('consent schedules odd-month publication wake', () async {
    await scheduler.setConsent(true);
    final result = await scheduler.reconcile(
      nowLocal: DateTime(2026, 9, 24, 9),
      periodId: '115-07-08',
    );
    expect(result.nextTargetLocal, DateTime(2026, 9, 25, 14));
    expect(platform.scheduled.single, DateTime(2026, 9, 25, 14));
  });

  test('foreground catch-up detects missed attempt from persisted state', () async {
    await scheduler.setConsent(true);
    await scheduler.recordAttemptStarted(
      nowLocal: DateTime(2026, 9, 25, 14, 10),
      periodId: '115-07-08',
    );
    await scheduler.recordAttemptFinished(
      periodId: '115-07-08',
      generalDatasetPromoted: true,
      cloudExclusiveDatasetPromoted: false,
    );
    expect(
      await scheduler.foregroundCatchUpDue(
        nowLocal: DateTime(2026, 9, 25, 14, 45),
        periodId: '115-07-08',
      ),
      isTrue,
    );
  });

  test('both promoted domains cancel future wake', () async {
    await scheduler.setConsent(true);
    await scheduler.recordAttemptStarted(
      nowLocal: DateTime(2026, 9, 25, 14),
      periodId: '115-07-08',
    );
    await scheduler.recordAttemptFinished(
      periodId: '115-07-08',
      generalDatasetPromoted: true,
      cloudExclusiveDatasetPromoted: true,
    );
    final result = await scheduler.reconcile(
      nowLocal: DateTime(2026, 9, 25, 14, 20),
      periodId: '115-07-08',
    );
    expect(result.currentPeriodComplete, isTrue);
    expect(result.nextTargetLocal, isNull);
    expect(platform.cancelCount, greaterThanOrEqualTo(1));
  });

  test('app-wide wake capture persists a foreground catch-up marker', () async {
    await scheduler.setConsent(true);
    platform.wake = InvoiceAwardNativeWake(
      targetLocal: DateTime(2026, 9, 25, 14),
      receivedAtLocal: DateTime(2026, 9, 25, 14, 7),
    );

    expect(await scheduler.captureNativeWakeForForeground(), isTrue);
    final state = scheduler.repository.load();
    expect(state.hasPendingForegroundCatchUp, isTrue);
    expect(
      state.pendingForegroundCatchUpAtLocal,
      DateTime(2026, 9, 25, 14, 7),
    );

    await scheduler.recordAttemptStarted(
      nowLocal: DateTime(2026, 9, 25, 14, 8),
      periodId: '115-07-08',
    );
    expect(
      scheduler.repository.load().hasPendingForegroundCatchUp,
      isFalse,
    );
  });

  test('opt-out discards native wake without persisting catch-up', () async {
    await scheduler.setConsent(false);
    platform.wake = InvoiceAwardNativeWake(
      targetLocal: DateTime(2026, 9, 25, 14),
      receivedAtLocal: DateTime(2026, 9, 25, 14, 7),
    );

    expect(await scheduler.captureNativeWakeForForeground(), isFalse);
    expect(
      scheduler.repository.load().hasPendingForegroundCatchUp,
      isFalse,
    );
    expect(platform.cancelCount, greaterThanOrEqualTo(1));
  });

  test('native due marker is consumable without granting network authority', () async {
    platform.wake = InvoiceAwardNativeWake(
      targetLocal: DateTime(2026, 9, 25, 14),
      receivedAtLocal: DateTime(2026, 9, 25, 14, 7),
    );
    final wake = await scheduler.consumeNativeWake();
    expect(wake?.targetLocal, DateTime(2026, 9, 25, 14));
    expect(platform.wake, isNull);
  });
}

class _FakePlatform implements InvoiceAwardPlatformWakeScheduler {
  final List<DateTime> scheduled = <DateTime>[];
  int cancelCount = 0;
  InvoiceAwardNativeWake? wake;

  @override
  Future<void> schedule(DateTime targetLocal) async {
    scheduled.add(targetLocal);
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<InvoiceAwardNativeWake?> consumeDue() async {
    final result = wake;
    wake = null;
    return result;
  }
}
