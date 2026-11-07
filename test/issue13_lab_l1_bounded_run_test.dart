import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/issue13_lab_l1_bounded_run.dart';
import 'package:my_finance_app/issue13_lab_l1_cursor.dart';

void main() {
  test('consecutive batches stop at final page with durable cursor', () async {
    var next = 1, calls = 0, used = 0;
    final result = await LabL1BoundedRun.run(
      readNextPage: () async => next,
      retainedBytes: () async => used,
      captureNext: () async {
        calls++;
        final first = next;
        final last = first == 1 ? 4 : 6;
        next = last + 1;
        used += 1200;
        return LabL1Batch(File('l1-pages-$first-$calls.jsonl'), last, 6);
      },
    );
    expect(calls, 2);
    expect(result.batches, 2);
    expect(result.nextPage, 7);
    expect(result.reachedFinalPage, isTrue);
  });

  test('batch quota cannot be reported as full-page evidence', () async {
    var next = 1, calls = 0;
    final result = await LabL1BoundedRun.run(
      maxBatches: 2,
      readNextPage: () async => next,
      retainedBytes: () async => 0,
      captureNext: () async {
        calls++;
        final first = next;
        next += 4;
        return LabL1Batch(File('batch-$first'), first + 3, 100);
      },
    );
    expect(calls, 2);
    expect(result.nextPage, 9);
    expect(result.reachedFinalPage, isFalse);
  });

  test('storage quota refuses native dispatch before creating files', () async {
    var calls = 0;
    await expectLater(LabL1BoundedRun.run(
      readNextPage: () async => 1,
      retainedBytes: () async => LabL1BoundedRun.maxRetainedBytes -
          LabL1BoundedRun.maxBatchBytes + 1,
      captureNext: () async {
        calls++;
        return LabL1Batch(File('unused'), 4, 10);
      },
    ), throwsA(isA<StateError>().having((e) => e.toString(),
        'quota', contains('L1_RETAINED_STORAGE_BUDGET_HOLD'))));
    expect(calls, 0);
  });

  test('missing cursor fsync or count drift is HOLD', () async {
    await expectLater(LabL1BoundedRun.run(
      readNextPage: () async => 1,
      retainedBytes: () async => 100,
      captureNext: () async => LabL1Batch(File('batch'), 4, 12),
    ), throwsA(isA<StateError>().having((e) => e.toString(),
        'cursor', contains('L1_BATCH_CURSOR_NOT_DURABLE'))));
    var next = 1, calls = 0;
    await expectLater(LabL1BoundedRun.run(
      readNextPage: () async => next,
      retainedBytes: () async => 0,
      captureNext: () async {
        calls++;
        final first = next;
        next += 4;
        return LabL1Batch(File('batch'), first + 3, calls == 1 ? 12 : 13);
      },
    ), throwsA(isA<StateError>().having((e) => e.toString(),
        'drift', contains('L1_BATCH_COVERAGE_OR_COUNT_DRIFT'))));
  });

  test('timeout cannot retry an unconfirmed native process', () async {
    final pending = Completer<LabL1Batch>();
    var calls = 0;
    await expectLater(LabL1BoundedRun.run(
      batchTimeout: const Duration(milliseconds: 10),
      readNextPage: () async => 1,
      retainedBytes: () async => 0,
      captureNext: () {
        calls++;
        return pending.future;
      },
    ), throwsA(isA<StateError>().having((e) => e.toString(),
        'timeout', contains('L1_NATIVE_TIMEOUT_PROCESS_UNCONFIRMED'))));
    expect(calls, 1);
  });
}
