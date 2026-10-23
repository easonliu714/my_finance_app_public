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
          'page_number': 0,
          'page_count': 0,
          'pages_read': 0,
          'stage_elapsed_ms': 0,
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
    test('accepts six actual Kotlin Running stage geometries', () {
      final stages = <Map<String, dynamic>>[
        <String, dynamic>{
          'stage': 'PLATFORM_SOURCE_SHA256',
          'source_bytes_read': 50000000,
        },
        <String, dynamic>{
          'stage': 'PLATFORM_RENDERER_OPEN_BEGIN',
          'source_bytes_read': 135200798,
        },
        <String, dynamic>{
          'stage': 'PLATFORM_RENDERER_OPEN_WAIT',
          'source_bytes_read': 135200798,
          'stage_elapsed_ms': 1500,
        },
        <String, dynamic>{
          'stage': 'PLATFORM_RENDERER_OPEN_OK',
          'source_bytes_read': 135200798,
          'page_count': 87000,
        },
        <String, dynamic>{
          'stage': 'PLATFORM_RENDERER_PAGE_BEGIN',
          'source_bytes_read': 135200798,
          'candidate_index': 1,
          'page_number': 43500,
          'page_count': 87000,
          'pages_read': 12,
        },
        <String, dynamic>{
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'source_bytes_read': 135200798,
          'candidate_index': 1,
          'page_number': 43500,
          'page_count': 87000,
          'pages_read': 13,
        },
      ];
      for (final fields in stages) {
        expect(
          violation(running()..addAll(fields)),
          isNull,
          reason: fields['stage'].toString(),
        );
      }
    });

    test('rejects missing and forged native stage', () {
      expect(
        violation(running()..remove('stage')),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_INVALID',
      );
      expect(
        violation(running()..['stage'] = 'PLATFORM_RENDERER_COMPLETE'),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_INVALID',
      );
    });

    test('rejects absent page geometry and elapsed fields', () {
      for (final field in <String>[
        'page_number',
        'page_count',
        'pages_read',
        'stage_elapsed_ms',
      ]) {
        expect(
          violation(running()..remove(field)),
          'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_EVIDENCE_INVALID',
        );
      }
      expect(
        violation(running()..['stage_elapsed_ms'] = -1),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_EVIDENCE_INVALID',
      );
    });

    test('rejects impossible page count, page number, and read count', () {
      expect(
        violation(running()..['page_count'] = -1),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_EVIDENCE_INVALID',
      );
      expect(
        violation(running()..addAll(<String, dynamic>{
          'page_count': 10,
          'page_number': 11,
        })),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_EVIDENCE_INVALID',
      );
      expect(
        violation(running()..addAll(<String, dynamic>{
          'page_count': 10,
          'pages_read': 11,
        })),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_EVIDENCE_INVALID',
      );
    });

    test('rejects source SHA stage with fabricated renderer progress', () {
      expect(
        violation(running()..['page_count'] = 1),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID',
      );
      expect(
        violation(running()..['candidate_index'] = 1),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID',
      );
    });

    test('rejects renderer opening without full source-byte custody', () {
      expect(
        violation(running()..['stage'] = 'PLATFORM_RENDERER_OPEN_WAIT'),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID',
      );
      expect(
        violation(running()..addAll(<String, dynamic>{
          'stage': 'PLATFORM_RENDERER_OPEN_OK',
          'source_bytes_read': 135200798,
        })),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID',
      );
    });

    test('rejects renderer search with missing page or candidate evidence', () {
      expect(
        violation(running()..addAll(<String, dynamic>{
          'stage': 'PLATFORM_RENDERER_PAGE_BEGIN',
          'source_bytes_read': 135200798,
          'page_count': 87000,
          'page_number': 1,
        })),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID',
      );
      expect(
        violation(running()..addAll(<String, dynamic>{
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'source_bytes_read': 135200798,
          'candidate_index': 1,
          'page_count': 87000,
          'page_number': 1,
        })),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID',
      );
    });

  });
}
