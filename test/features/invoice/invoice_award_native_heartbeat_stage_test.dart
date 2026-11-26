import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
  group('native heartbeat UI evidence', () {
    test('fresh native open-begin remains the actual reported stage', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_BEGIN',
          heartbeatAge: const Duration(seconds: 2),
        ),
        'PLATFORM_RENDERER_OPEN_BEGIN',
      );
    });

    test('fresh native open-wait is not relabeled', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_WAIT',
          heartbeatAge: const Duration(seconds: 5),
        ),
        'PLATFORM_RENDERER_OPEN_WAIT',
      );
    });

    test('15 second boundary still preserves native evidence', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_SOURCE_SHA256',
          heartbeatAge: const Duration(seconds: 15),
        ),
        'PLATFORM_SOURCE_SHA256',
      );
    });

    test('stale open-begin never becomes synthetic open-wait', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_BEGIN',
          heartbeatAge: const Duration(seconds: 16),
        ),
        'PLATFORM_WORKER_HEARTBEAT_STALE',
      );
    });

    test('stale progress in any native stage cannot claim new progress', () {
      for (final stage in <String>[
        'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'PLATFORM_SOURCE_SHA256',
        'PLATFORM_RENDERER_OPEN_WAIT',
      ]) {
        expect(
          cloudAwardNativeHeartbeatDisplayStage(
            nativeStage: stage,
            heartbeatAge: const Duration(minutes: 4),
          ),
          'PLATFORM_WORKER_HEARTBEAT_STALE',
        );
      }
    });

    test('future-dated native heartbeat is not treated as fresh', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_BEGIN',
          heartbeatAge: const Duration(seconds: -1),
        ),
        'PLATFORM_WORKER_HEARTBEAT_STALE',
      );
    });
    test('fresh native heartbeat does not require a liveness probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: 2)),
        isFalse,
      );
    });

    test('exact heartbeat age boundary does not probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: 15)),
        isFalse,
      );
    });

    test('expired heartbeat requires a liveness probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: 16)),
        isTrue,
      );
    });

    test('future native clock requires a liveness probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: -1)),
        isTrue,
      );
    });
  });

  group('native COMPLETE terminal provenance', () {
    final observedAt = DateTime.fromMillisecondsSinceEpoch(1800000000000);
    final priorHeartbeatAt =
        observedAt.subtract(const Duration(seconds: 1));

    Map<String, dynamic> validTerminal() => <String, dynamic>{
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'stage': 'PLATFORM_RENDERER_COMPLETE',
          'worker_pid': 321,
          'updated_at_ms': observedAt.millisecondsSinceEpoch,
        };

    String? violation(Map<String, dynamic> terminal, {int priorPid = 321}) =>
        cloudAwardNativeCompleteTerminalViolation(
          terminal: terminal,
          priorWorkerPid: priorPid,
          observedAt: observedAt,
          priorHeartbeatAt: priorHeartbeatAt,
        );

    test('accepts native complete identity with matching prior PID', () {
      expect(violation(validTerminal()), isNull);
    });
    test('accepts first terminal with a positive PID', () {
      expect(violation(validTerminal(), priorPid: 0), isNull);
    });
    test('rejects absent engine', () {
      expect(
        violation(validTerminal()..remove('engine')),
        'CLOUD_AWARD_CANDIDATE_WORKER_ENGINE_MISMATCH',
      );
    });
    test('rejects non-complete stage', () {
      expect(
        violation(validTerminal()..['stage'] = 'PLATFORM_RENDERER_OPEN_WAIT'),
        'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_STAGE_MISMATCH',
      );
    });
    test('rejects missing PID', () {
      expect(
        violation(validTerminal()..remove('worker_pid')),
        'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_PID_MISSING',
      );
    });
    test('rejects changed worker PID', () {
      expect(
        violation(validTerminal()..['worker_pid'] = 322),
        'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_PID_MISMATCH',
      );
    });
    test('rejects future-dated terminal clock', () {
      expect(
        violation(validTerminal()..['updated_at_ms'] =
            observedAt.add(const Duration(seconds: 1)).millisecondsSinceEpoch),
        'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_CLOCK_INVALID',
      );
    });
    test('rejects terminal timestamp older than last native heartbeat', () {
      expect(
        violation(validTerminal()..['updated_at_ms'] =
            priorHeartbeatAt.subtract(const Duration(milliseconds: 1))
                .millisecondsSinceEpoch),
        'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_CLOCK_INVALID',
      );
    });
    test('rejects missing terminal timestamp', () {
      expect(
        violation(validTerminal()..remove('updated_at_ms')),
        'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_CLOCK_INVALID',
      );
    });
  });

  group('native FAILED terminal current envelope', () {
    final observedAt = DateTime.fromMillisecondsSinceEpoch(1800000000000);
    final priorHeartbeatAt =
        observedAt.subtract(const Duration(seconds: 1));

    Map<String, dynamic> validFailedTerminal() => <String, dynamic>{
          'request_id': 'request-1',
          'status': 'failed',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'error': 'PLATFORM_WORKER_SOURCE_MISSING',
          'updated_at_ms': observedAt.millisecondsSinceEpoch,
        };

    String? violation(Map<String, dynamic> terminal,
            {DateTime? heartbeatAt}) =>
        cloudAwardNativeFailedTerminalViolation(
          terminal: terminal,
          observedAt: observedAt,
          priorHeartbeatAt: heartbeatAt,
        );

    test('accepts current Kotlin failed publisher envelope', () {
      expect(violation(validFailedTerminal()), isNull);
    });
    test('accepts bounded Kotlin exception-class suffix', () {
      expect(
        violation(validFailedTerminal()
          ..['error'] = 'PLATFORM_WORKER_FAILED:IllegalStateException'),
        isNull,
      );
    });
    test('early failure without native heartbeat is not false clock failure',
        () {
      expect(
        violation(validFailedTerminal()
          ..['updated_at_ms'] = observedAt
              .subtract(const Duration(seconds: 20))
              .millisecondsSinceEpoch),
        isNull,
      );
    });
    test('rejects incorrect failed status', () {
      expect(
        violation(validFailedTerminal()..['status'] = 'complete'),
        'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_STATUS_INVALID',
      );
    });
    test('rejects failed terminal engine mismatch', () {
      expect(
        violation(validFailedTerminal()..remove('engine')),
        'CLOUD_AWARD_CANDIDATE_WORKER_ENGINE_MISMATCH',
      );
    });
    test('rejects missing failed terminal timestamp', () {
      expect(
        violation(validFailedTerminal()..remove('updated_at_ms')),
        'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_CLOCK_INVALID',
      );
    });
    test('rejects future-dated failed terminal', () {
      expect(
        violation(validFailedTerminal()
          ..['updated_at_ms'] = observedAt
              .add(const Duration(milliseconds: 1))
              .millisecondsSinceEpoch),
        'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_CLOCK_INVALID',
      );
    });
    test('rejects failure timestamp older than observed native heartbeat',
        () {
      expect(
        violation(
          validFailedTerminal()
            ..['updated_at_ms'] = priorHeartbeatAt
                .subtract(const Duration(milliseconds: 1))
                .millisecondsSinceEpoch,
          heartbeatAt: priorHeartbeatAt,
        ),
        'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_CLOCK_INVALID',
      );
    });
    test('rejects missing failed terminal error', () {
      expect(
        violation(validFailedTerminal()..remove('error')),
        'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_ERROR_INVALID',
      );
    });
    test('rejects unbounded or untrusted failure text', () {
      for (final error in <String>[
        'http://untrusted.invalid/data',
        'PLATFORM_WORKER_FAILED:${List<String>.filled(130, 'X').join()}',
      ]) {
        expect(
          violation(validFailedTerminal()..['error'] = error),
          'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_ERROR_INVALID',
        );
      }
    });
  });
}
