import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_automatic_refresh_runtime.dart';
import 'package:my_finance_app/features/invoice/invoice_award_period_catalog.dart';

void main() {
  group('InvoiceAwardAutomaticRefreshCoordinator', () {
    test('opt-out is a hard zero-execution boundary', () async {
      final repository = _MemoryStateRepository(
        const InvoiceAwardAutomaticRefreshState.initial(),
      );
      final executor = _FakeExecutor(complete: true);
      final coordinator = InvoiceAwardAutomaticRefreshCoordinator(
        stateRepository: repository,
        executor: executor,
      );

      final result = await coordinator.runForegroundCatchUp(
        nowLocal: DateTime(2026, 9, 25, 14, 30),
      );

      expect(
        result.status,
        InvoiceAwardAutomaticRefreshStatus.skippedOptOut,
      );
      expect(executor.calls, 0);
    });

    test('due foreground catch-up executes once and seals completed period',
        () async {
      final repository = _MemoryStateRepository(
        const InvoiceAwardAutomaticRefreshState(
          automaticRefreshConsented: true,
        ),
      );
      final executor = _FakeExecutor(complete: true);
      final coordinator = InvoiceAwardAutomaticRefreshCoordinator(
        stateRepository: repository,
        executor: executor,
      );
      final now = DateTime(2026, 9, 25, 14, 30);

      final result =
          await coordinator.runForegroundCatchUp(nowLocal: now);

      expect(
        result.status,
        InvoiceAwardAutomaticRefreshStatus.completed,
      );
      expect(result.periodId, '115-07-08');
      expect(executor.calls, 1);
      expect(repository.state.lastAttemptUtc, now.toUtc());
      expect(repository.state.lastCompletedPeriodId, '115-07-08');
      expect(repository.state.lastFailureCode, isNull);

      final repeated =
          await coordinator.runForegroundCatchUp(nowLocal: now.add(
        const Duration(minutes: 1),
      ));
      expect(
        repeated.status,
        InvoiceAwardAutomaticRefreshStatus.skippedNotDue,
      );
      expect(executor.calls, 1);
    });

    test('incomplete authority is durable and eligible for bounded retry',
        () async {
      final repository = _MemoryStateRepository(
        const InvoiceAwardAutomaticRefreshState(
          automaticRefreshConsented: true,
        ),
      );
      final executor = _FakeExecutor(
        complete: false,
        failureCode: 'CLOUD_AUTHORITY_INCOMPLETE',
      );
      final coordinator = InvoiceAwardAutomaticRefreshCoordinator(
        stateRepository: repository,
        executor: executor,
      );
      final first = DateTime(2026, 9, 25, 14, 1);

      final result =
          await coordinator.runForegroundCatchUp(nowLocal: first);
      expect(
        result.status,
        InvoiceAwardAutomaticRefreshStatus.incomplete,
      );
      expect(
        repository.state.lastFailureCode,
        'CLOUD_AUTHORITY_INCOMPLETE',
      );
      expect(repository.state.lastCompletedPeriodId, isNull);
      expect(executor.calls, 1);

      final tooSoon = await coordinator.runForegroundCatchUp(
        nowLocal: first.add(const Duration(minutes: 20)),
      );
      expect(
        tooSoon.status,
        InvoiceAwardAutomaticRefreshStatus.skippedNotDue,
      );
      expect(executor.calls, 1);

      final retry = await coordinator.runForegroundCatchUp(
        nowLocal: first.add(const Duration(minutes: 31)),
      );
      expect(
        retry.status,
        InvoiceAwardAutomaticRefreshStatus.incomplete,
      );
      expect(executor.calls, 2);
    });

    test('executor period mismatch fails closed', () async {
      final repository = _MemoryStateRepository(
        const InvoiceAwardAutomaticRefreshState(
          automaticRefreshConsented: true,
        ),
      );
      final executor = _FakeExecutor(
        complete: true,
        overridePeriodId: '115-05-06',
      );
      final coordinator = InvoiceAwardAutomaticRefreshCoordinator(
        stateRepository: repository,
        executor: executor,
      );

      final result = await coordinator.runForegroundCatchUp(
        nowLocal: DateTime(2026, 9, 25, 15),
      );

      expect(
        result.status,
        InvoiceAwardAutomaticRefreshStatus.failed,
      );
      expect(
        result.failureCode,
        'AUTOMATIC_REFRESH_PERIOD_MISMATCH',
      );
      expect(repository.state.lastCompletedPeriodId, isNull);
    });

    test('before publication target never executes', () async {
      final repository = _MemoryStateRepository(
        const InvoiceAwardAutomaticRefreshState(
          automaticRefreshConsented: true,
        ),
      );
      final executor = _FakeExecutor(complete: true);
      final coordinator = InvoiceAwardAutomaticRefreshCoordinator(
        stateRepository: repository,
        executor: executor,
      );

      final result = await coordinator.runForegroundCatchUp(
        nowLocal: DateTime(2026, 9, 25, 13, 59),
      );

      expect(
        result.status,
        InvoiceAwardAutomaticRefreshStatus.skippedNotDue,
      );
      expect(executor.calls, 0);
    });
  });
}

class _MemoryStateRepository
    implements InvoiceAwardAutomaticRefreshStateRepository {
  _MemoryStateRepository(this.state);

  InvoiceAwardAutomaticRefreshState state;

  @override
  Future<InvoiceAwardAutomaticRefreshState> read() async => state;

  @override
  Future<void> replace(InvoiceAwardAutomaticRefreshState value) async {
    state = value;
  }
}

class _FakeExecutor implements InvoiceAwardAutomaticRefreshExecutor {
  _FakeExecutor({
    required this.complete,
    this.failureCode,
    this.overridePeriodId,
  });

  final bool complete;
  final String? failureCode;
  final String? overridePeriodId;
  int calls = 0;

  @override
  Future<InvoiceAwardAutomaticRefreshExecutionResult> execute({
    required InvoiceAwardSelectablePeriod period,
    required DateTime nowLocal,
  }) async {
    calls += 1;
    return InvoiceAwardAutomaticRefreshExecutionResult(
      periodId: overridePeriodId ?? period.period.id,
      generalAuthorityReady: complete,
      cloudAuthorityReady: complete,
      failureCode: failureCode,
    );
  }
}
