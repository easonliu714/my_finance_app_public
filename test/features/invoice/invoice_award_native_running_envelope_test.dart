import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
  group('native Running envelope / current Kotlin contract', () {
    final observedAt = DateTime.fromMillisecondsSinceEpoch(2000000);
    final priorHeartbeatAt = DateTime.fromMillisecondsSinceEpoch(1998000);

    Map<String, dynamic> running() => <String, dynamic>{
          'request_id': 'request-bound-elsewhere',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 321,
          'stage': 'PLATFORM_SOURCE_SHA256',
          'candidate_index': 0,
          'candidate_count': 47,
          'source_bytes_read': 0,
          'source_bytes_total': 135200798,
          'updated_at_ms': 1999000,
        };

    String? violation(Map<String, dynamic> item, {
      int priorPid = 321,
      DateTime? priorHeartbeat,
    }) =>
        cloudAwardNativeRunningEnvelopeViolation(
          running: item,
          expectedCandidateCount: 47,
          expectedSourceBytes: 135200798,
          priorWorkerPid: priorPid,
          observedAt: observedAt,
          priorHeartbeatAt: priorHeartbeat,
        );

    test('accepts native first Running envelope', () {
      expect(violation(running(), priorPid: 0), isNull);
    });

    test('accepts same PID and monotonic heartbeats', () {
      expect(violation(running(), priorHeartbeat: priorHeartbeatAt), isNull);
    });

    test('rejects incorrect status or engine', () {
      for (final field in <String>['status', 'engine']) {
        expect(
          violation(running()..remove(field)),
          'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_ENVELOPE_INVALID',
        );
      }
    });

    test('rejects missing or changed PID', () {
      expect(
        violation(running()..remove('worker_pid')),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PID_MISMATCH',
      );
      expect(
        violation(running()..['worker_pid'] = 322),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PID_MISMATCH',
      );
    });

    test('rejects candidate-universe cardinality mismatch', () {
      expect(
        violation(running()..['candidate_count'] = 46),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CANDIDATE_MISMATCH',
      );
    });

    test('rejects index outside the candidate range', () {
      for (final idx in <int>[-1, 48]) {
        expect(
          violation(running()..['candidate_index'] = idx),
          'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CANDIDATE_MISMATCH',
        );
      }
    });

    test('rejects bytes total mismatch', () {
      expect(
        violation(running()..['source_bytes_total'] = 0),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_BYTES_MISMATCH',
      );
    });

    test('rejects read bytes outside source length', () {
      expect(
        violation(running()..['source_bytes_read'] = 135200799),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_BYTES_MISMATCH',
      );
    });

    test('rejects future native Running clock', () {
      expect(
        violation(running()..['updated_at_ms'] = 2000001),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CLOCK_INVALID',
      );
    });

    test('rejects native Running clock regression', () {
      expect(
        violation(running()..['updated_at_ms'] = 1997999,
            priorHeartbeat: priorHeartbeatAt),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CLOCK_INVALID',
      );
    });

    test('accepts exact equal timestamp on atomic result re-read', () {
      expect(
        violation(running()..['updated_at_ms'] = 1998000,
            priorHeartbeat: priorHeartbeatAt),
        isNull,
      );
    });
  });
}
