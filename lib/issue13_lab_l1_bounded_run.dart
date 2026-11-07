import 'dart:math' as math;
import 'issue13_lab_l1_cursor.dart';

/// Lab-only capture: cursor completion is not proof of official extraction
/// completeness, global NOT_WIN, production integration, or Owner acceptance.
class LabL1BoundedRunResult {
  const LabL1BoundedRunResult(this.batches, this.nextPage, this.pageCount);
  final int batches;
  final int nextPage;
  final int? pageCount;
  bool get reachedFinalPage => pageCount != null && nextPage == pageCount! + 1;
}

class LabL1BoundedRun {
  static const maxBatchesPerRun = 8;
  static const maxBatchBytes = 4000000;
  static const maxRetainedBytes = 256 * 1024 * 1024;
  static const defaultBatchTimeout = Duration(minutes: 2);

  /// Each callback must verify the native JSONL and fsync/rename the cursor.
  /// On timeout, do not retry: the native process might still be running.
  static Future<LabL1BoundedRunResult> run({
    required Future<int> Function() readNextPage,
    required Future<int> Function() retainedBytes,
    required Future<LabL1Batch> Function() captureNext,
    int maxBatches = maxBatchesPerRun,
    int storageLimitBytes = maxRetainedBytes,
    Duration batchTimeout = defaultBatchTimeout,
  }) async {
    if (maxBatches < 1 || maxBatches > maxBatchesPerRun ||
        storageLimitBytes < maxBatchBytes ||
        batchTimeout <= Duration.zero) {
      throw ArgumentError('L1_BOUNDED_RUN_LIMIT_INVALID');
    }
    var next = await readNextPage();
    if (next < 1 || next > 100000) {
      throw StateError('L1_CURSOR_INVALID_OR_COMPLETE');
    }
    int? total;
    var batches = 0;
    for (var i = 0; i < maxBatches; i++) {
      final before = await retainedBytes();
      if (before < 0 || before > storageLimitBytes - maxBatchBytes) {
        throw StateError('L1_RETAINED_STORAGE_BUDGET_HOLD');
      }
      final first = next;
      final batch = await captureNext().timeout(batchTimeout,
          onTimeout: () => throw StateError(
              'L1_NATIVE_TIMEOUT_PROCESS_UNCONFIRMED'));
      if (batch.count < 1 || batch.count > 100000 ||
          first > batch.count ||
          batch.last != math.min(first + 3, batch.count) ||
          (total != null && batch.count != total)) {
        throw StateError('L1_BATCH_COVERAGE_OR_COUNT_DRIFT');
      }
      final durable = await readNextPage();
      if (durable != batch.last + 1) {
        throw StateError('L1_BATCH_CURSOR_NOT_DURABLE');
      }
      final after = await retainedBytes();
      if (after < 0 || after > storageLimitBytes) {
        throw StateError('L1_RETAINED_STORAGE_BUDGET_HOLD');
      }
      total = batch.count;
      next = durable;
      batches++;
      if (next > total) break;
    }
    return LabL1BoundedRunResult(batches, next, total);
  }
}
