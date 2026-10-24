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
      int? priorSourceBytesRead,
      int? priorSearchPagesRead,
      int? priorSearchCandidateIndex,
      int? priorSearchPageCount,
      int? priorSearchPageNumber,
    }) =>
        cloudAwardNativeRunningEnvelopeViolation(
          running: item,
          expectedCandidateCount: 47,
          expectedSourceBytes: 135200798,
          priorWorkerPid: priorPid,
          observedAt: observedAt,
          priorHeartbeatAt: priorHeartbeat,
          priorSourceBytesRead: priorSourceBytesRead,
          priorCandidateSearchPagesRead: priorSearchPagesRead,
          priorCandidateSearchIndex: priorSearchCandidateIndex,
          priorCandidateSearchPageCount: priorSearchPageCount,
          priorCandidateSearchPageNumber: priorSearchPageNumber,
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

    // Kotlin sha256File increments totalRead; no later verified Running
    // observation for the same request/PID may report fewer source bytes.
    test('rejects decreasing SHA256 byte count', () {
      expect(
        violation(running()..['source_bytes_read'] = 400,
            priorSourceBytesRead: 800),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_SOURCE_BYTES_REGRESSION',
      );
    });

    test('rejects completed hash bytes rolling back to partial', () {
      expect(
        violation(running()..['source_bytes_read'] = 1000,
            priorSourceBytesRead: 135200798),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_SOURCE_BYTES_REGRESSION',
      );
    });

    test('accepts zero, increasing, and repeated source byte counts', () {
      for (final sample in <(int, int)>[
        (0, 0),
        (0, 400),
        (400, 400),
        (400, 135200798),
      ]) {
        expect(
          violation(running()..['source_bytes_read'] = sample.$2,
              priorSourceBytesRead: sample.$1),
          isNull,
        );
      }
    });

    test('accepts OPEN_WAIT and OPEN_OK at unchanged complete bytes', () {
      for (final stage in <String>[
        'PLATFORM_RENDERER_OPEN_WAIT',
        'PLATFORM_RENDERER_OPEN_OK',
      ]) {
        expect(
          violation(
            running()
              ..addAll(<String, dynamic>{
                'stage': stage,
                'source_bytes_read': 135200798,
                'page_count': stage == 'PLATFORM_RENDERER_OPEN_OK' ? 87000 : 0,
              }),
            priorSourceBytesRead: 135200798,
          ),
          isNull,
          reason: stage,
        );
      }
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

    test('search page count regression is fail-closed for the same PID', () {
      final current = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'source_bytes_read': 135200798,
        'candidate_index': 1,
        'page_number': 43500,
        'page_count': 87000,
        'pages_read': 12,
      });
      expect(
        violation(current, priorHeartbeat: priorHeartbeatAt,
            priorSearchPagesRead: 13),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGES_READ_REGRESSION',
      );
    });

    test('equal and increasing search page counts are valid', () {
      for (final count in <int>[13, 14]) {
        final current = running()..addAll(<String, dynamic>{
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'source_bytes_read': 135200798,
          'candidate_index': 1,
          'page_number': 43500,
          'page_count': 87000,
          'pages_read': count,
        });
        expect(violation(current, priorSearchPagesRead: 13), isNull);
      }
    });

    test('opening stages after verified SEARCH fail closed', () {
      final waiting = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_WAIT',
        'source_bytes_read': 135200798,
      });
      final opened = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_OK',
        'source_bytes_read': 135200798,
        'page_count': 87000,
      });
      expect(violation(waiting, priorSearchPagesRead: 13), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
      expect(violation(opened, priorSearchPagesRead: 13), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
    });

    // Native candidates.forEachIndexed emits SEARCH in sequential order.
    test('later SEARCH candidate index regression is fail-closed', () {
      final current = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'source_bytes_read': 135200798,
        'candidate_index': 1,
        'page_number': 43500,
        'page_count': 87000,
        'pages_read': 13,
      });
      expect(
        violation(current, priorHeartbeat: priorHeartbeatAt,
            priorSearchCandidateIndex: 2),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CANDIDATE_INDEX_REGRESSION',
      );
    });

    test('equal and increasing SEARCH candidate indices are valid', () {
      for (final index in <int>[2, 3]) {
        final current = running()..addAll(<String, dynamic>{
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'source_bytes_read': 135200798,
          'candidate_index': index,
          'page_number': 43500,
          'page_count': 87000,
          'pages_read': 13,
        });
        expect(violation(current, priorSearchCandidateIndex: 2), isNull);
      }
    });

    test('opening stages cannot follow verified SEARCH candidate order', () {
      final waiting = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_WAIT',
        'source_bytes_read': 135200798,
      });
      final opened = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_OK',
        'source_bytes_read': 135200798,
        'page_count': 87000,
      });
      expect(violation(waiting, priorSearchCandidateIndex: 2,
          priorSearchPagesRead: 13), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
      expect(violation(opened, priorSearchCandidateIndex: 2,
          priorSearchPagesRead: 13), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
    });


    // PdfRenderer.pageCount is immutable for one verified SEARCH request.
    test('rejects changed SEARCH page count for the same worker', () {
      final current = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'source_bytes_read': 135200798,
        'candidate_index': 1,
        'page_number': 43500,
        'page_count': 87001,
        'pages_read': 13,
      });
      expect(
        violation(current, priorHeartbeat: priorHeartbeatAt,
            priorSearchPageCount: 87000),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_COUNT_CHANGED',
      );
    });

    test('accepts unchanged SEARCH page count', () {
      final current = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'source_bytes_read': 135200798,
        'candidate_index': 1,
        'page_number': 43500,
        'page_count': 87000,
        'pages_read': 13,
      });
      expect(violation(current, priorSearchPageCount: 87000), isNull);
    });


    // Kotlin SEARCH is emitted only after a previously uncached page is read.
    test('same pages_read with changed SEARCH page fails closed', () {
      final current = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'source_bytes_read': 135200798,
        'candidate_index': 1,
        'page_number': 43501,
        'page_count': 87000,
        'pages_read': 13,
      });
      expect(
        violation(current, priorSearchPagesRead: 13,
            priorSearchPageNumber: 43500),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_SEARCH_PAGE_IDENTITY_INVALID',
      );
    });

    test('increased pages_read with same SEARCH page fails closed', () {
      final current = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'source_bytes_read': 135200798,
        'candidate_index': 1,
        'page_number': 43500,
        'page_count': 87000,
        'pages_read': 14,
      });
      expect(
        violation(current, priorSearchPagesRead: 13,
            priorSearchPageNumber: 43500),
        'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_SEARCH_PAGE_IDENTITY_INVALID',
      );
    });

    test('duplicate SEARCH poll and new sparse page are valid', () {
      for (final pair in <(int, int)>[(13, 43500), (14, 65000)]) {
        final current = running()..addAll(<String, dynamic>{
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'source_bytes_read': 135200798,
          'candidate_index': 1,
          'page_number': pair.$2,
          'page_count': 87000,
          'pages_read': pair.$1,
        });
        expect(violation(current, priorSearchPagesRead: 13,
            priorSearchPageNumber: 43500), isNull);
      }
    });

    test('opening stages cannot follow verified SEARCH page identity', () {
      final waiting = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_WAIT',
        'source_bytes_read': 135200798,
      });
      final opened = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_OK',
        'source_bytes_read': 135200798,
        'page_count': 87000,
      });
      expect(violation(waiting, priorSearchPagesRead: 13,
          priorSearchPageNumber: 43500), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
      expect(violation(opened, priorSearchPagesRead: 13,
          priorSearchPageNumber: 43500), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
    });

    test('opening stages cannot follow verified SEARCH page-count authority', () {
      final waiting = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_WAIT',
        'source_bytes_read': 135200798,
      });
      final opened = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_OPEN_OK',
        'source_bytes_read': 135200798,
        'page_count': 87001,
      });
      expect(violation(waiting, priorSearchPageCount: 87000,
          priorSearchPagesRead: 13), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
      expect(violation(opened, priorSearchPageCount: 87000,
          priorSearchPagesRead: 13), 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION');
    });
    // Once SEARCH has been verified, even a newer timestamp cannot make an
    // opening-stage write valid. Before SEARCH, all opening stages remain valid.
    test('rejects all pre-search stages after verified SEARCH', () {
      for (final stage in <String>[
        'PLATFORM_SOURCE_SHA256',
        'PLATFORM_RENDERER_OPEN_BEGIN',
        'PLATFORM_RENDERER_OPEN_WAIT',
        'PLATFORM_RENDERER_OPEN_OK',
      ]) {
        final current = running()..addAll(<String, dynamic>{
          'stage': stage,
          'source_bytes_read': 135200798,
          'page_count': stage == 'PLATFORM_RENDERER_OPEN_OK' ? 87000 : 0,
        });
        expect(
          violation(current, priorSearchPagesRead: 13,
              priorSourceBytesRead: 135200798),
          'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION',
          reason: stage,
        );
        expect(
          violation(current, priorSourceBytesRead: 135200798),
          isNull,
          reason: 'Opening before SEARCH is legal: $stage',
        );
      }
    });

    test('PAGE_BEGIN after verified SEARCH remains legal', () {
      final nextPage = running()..addAll(<String, dynamic>{
        'stage': 'PLATFORM_RENDERER_PAGE_BEGIN',
        'source_bytes_read': 135200798,
        'candidate_index': 1,
        'page_number': 65000,
        'page_count': 87000,
        'pages_read': 13,
      });
      expect(
        violation(nextPage, priorSearchPagesRead: 13,
            priorSearchCandidateIndex: 1,
            priorSearchPageCount: 87000,
            priorSourceBytesRead: 135200798),
        isNull,
      );
    });

  });
}
