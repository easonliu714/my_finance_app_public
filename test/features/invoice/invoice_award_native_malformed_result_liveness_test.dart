import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_artifact_downloader.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_publication_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdf_text');
  const lookup = PdfiumCloudAwardSortedPdfCandidateLookup();
  late Directory directory;
  late File resultFile;
  late OfficialCloudAwardDownloadedArtifact artifact;
  late int probes;
  var sawPartial = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native_partial_liveness_');
    resultFile = File('${directory.path}/result.json');
    artifact = OfficialCloudAwardDownloadedArtifact(
      reference: OfficialCloudAwardArtifactReference(
        artifactId: 'fixture_sorted_AI_D.pdf',
        sourceUri: Uri.parse(
          'https://invoice.etax.nat.gov.tw/pdf/fixture_sorted_AI_D.pdf',
        ),
        periodId: 'fixture',
        tierCode: 'cloud-500',
      ),
      file: File('${directory.path}/fixture.pdf'),
      sizeBytes: 1000,
      sha256: List<String>.filled(64, 'a').join(),
    );
    probes = 0;
    sawPartial = false;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Map<String, Object?> staleRunning() => <String, Object?>{
        'request_id': 'req-test',
        'status': 'running',
        'engine': 'android-platform-pdfrenderer-candidate-search',
        'stage': 'PLATFORM_SOURCE_SHA256',
        'worker_pid': 4242,
        'candidate_index': 0,
        'candidate_count': 1,
        'source_bytes_read': 0,
        'source_bytes_total': 1000,
        'page_number': 0,
        'page_count': 0,
        'pages_read': 0,
        'stage_elapsed_ms': 0,
        'updated_at_ms': DateTime.now()
            .subtract(const Duration(seconds: 20))
            .millisecondsSinceEpoch,
      };

  Future<void> mockWorker({
    required bool alive,
    CloudAwardCandidateLookupCancellation? cancelAfterProbe,
    bool malformedFromStart = false,
    bool overrideLiveness = false,
    Map<String, Object?>? livenessOverride,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(
          malformedFromStart ? '{"request_id":' : jsonEncode(staleRunning()),
        );
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      if (call.method == 'getPlatformCandidateWorkerLiveness') {
        expect((call.arguments as Map)['workerPid'], 4242);
        probes += 1;
        cancelAfterProbe?.cancel();
        if (overrideLiveness) return livenessOverride;
        return <String, Object?>{
          'alive': alive,
          'pid': 4242,
          'processName': 'com.example.finance:platform_candidate_worker',
          'importance': alive ? 100 : -1,
          'exitReasonCode': alive ? -1 : 9,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
  }

  Future<CloudAwardSortedPdfCandidateMatchResult> lookupWith(
    CloudAwardCandidateLookupCancellation cancellation, {
    void Function(CloudAwardSortedPdfCandidateProgress)? onProgress,
  }) =>
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678'],
        cancellation: cancellation,
        onProgress: onProgress,
      );

  void replaceWithPartialJson(CloudAwardSortedPdfCandidateProgress progress) {
    if (!sawPartial) {
      sawPartial = true;
      resultFile.writeAsStringSync('{"request_id":');
    }
  }

  test('partial JSON after verified PID still detects OS process death',
      () async {
    await mockWorker(alive: false);
    final cancellation = CloudAwardCandidateLookupCancellation();
    await expectLater(
      lookupWith(cancellation, onProgress: replaceWithPartialJson)
          .timeout(const Duration(seconds: 7)),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'failure',
          contains(
            'CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_'
            'PLATFORM_SOURCE_SHA256_OS_EXIT_9',
          ),
        ),
      ),
    );
    expect(sawPartial, isTrue);
    expect(probes, 1);
    expect(await resultFile.exists(), isTrue);
  });

  test('alive PID retries partial JSON without promoting false COMPLETE',
      () async {
    final cancellation = CloudAwardCandidateLookupCancellation();
    await mockWorker(alive: true, cancelAfterProbe: cancellation);
    final stages = <String>[];
    await expectLater(
      lookupWith(
        cancellation,
        onProgress: (progress) {
          stages.add(progress.stage);
          replaceWithPartialJson(progress);
        },
      ).timeout(const Duration(seconds: 7)),
      throwsA(isA<CloudAwardCandidateLookupCancelled>()),
    );
    expect(sawPartial, isTrue);
    expect(probes, 1);
    expect(stages, contains('PLATFORM_WORKER_HEARTBEAT_STALE'));
    expect(stages, isNot(contains('PLATFORM_RENDERER_OPEN_WAIT')));
    expect(await resultFile.readAsString(), '{"request_id":');
  });

  test('malformed result without verified PID does not guess worker death',
      () async {
    final cancellation = CloudAwardCandidateLookupCancellation();
    await mockWorker(alive: false, malformedFromStart: true);
    Future<void>.delayed(
      const Duration(milliseconds: 350),
      cancellation.cancel,
    );
    await expectLater(
      lookupWith(cancellation).timeout(const Duration(seconds: 4)),
      throwsA(isA<CloudAwardCandidateLookupCancelled>()),
    );
    expect(probes, 0);
    expect(await resultFile.exists(), isTrue);
  });

  // Real temp-file + MethodChannel integration: an ambiguous liveness reply
  // must never be reclassified as a verified PROCESS_DIED observation.
  Future<void> expectInvalidLiveness(
    Map<String, Object?>? reply,
    String expectedViolation,
  ) async {
    await mockWorker(
      alive: true,
      overrideLiveness: true,
      livenessOverride: reply,
    );
    final cancellation = CloudAwardCandidateLookupCancellation();
    await expectLater(
      lookupWith(cancellation, onProgress: replaceWithPartialJson)
          .timeout(const Duration(seconds: 7)),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'fail-closed liveness violation',
          contains(expectedViolation),
        ),
      ),
    );
    expect(sawPartial, isTrue);
    expect(probes, 1);
    expect(await resultFile.readAsString(), '{"request_id":');
  }

  test('null liveness reply cannot be reported as verified process death',
      () async {
    await expectInvalidLiveness(
      null,
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_RESPONSE_INVALID',
    );
  });

  test('missing alive flag cannot be reported as verified process death',
      () async {
    await expectInvalidLiveness(
      <String, Object?>{
        'pid': 4242,
        'processName': 'com.example.finance:platform_candidate_worker',
        'exitReasonCode': -1,
      },
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_RESPONSE_INVALID',
    );
  });

  test('string alive flag cannot be reported as verified process death',
      () async {
    await expectInvalidLiveness(
      <String, Object?>{
        'alive': 'false',
        'pid': 4242,
        'processName': 'com.example.finance:platform_candidate_worker',
        'exitReasonCode': -1,
      },
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_RESPONSE_INVALID',
    );
  });

  test('mismatched liveness PID fails closed before accepting alive',
      () async {
    await expectInvalidLiveness(
      <String, Object?>{
        'alive': true,
        'pid': 4243,
        'processName': 'com.example.finance:platform_candidate_worker',
        'exitReasonCode': -1,
      },
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_PID_MISMATCH',
    );
  });

  test('wrong liveness process name fails closed before accepting alive',
      () async {
    await expectInvalidLiveness(
      <String, Object?>{
        'alive': true,
        'pid': 4242,
        'processName': 'com.example.finance:other_process',
        'exitReasonCode': -1,
      },
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_PROCESS_MISMATCH',
    );
  });

  // Real partial-result + observed PID integration: missing process-list
  // membership alone cannot establish a historical process death.
  test('no historical exit record stays liveness UNKNOWN', () async {
    await expectInvalidLiveness(
      <String, Object?>{
        'alive': false,
        'pid': 4242,
        'processName': 'com.example.finance:platform_candidate_worker',
        'exitReasonCode': -1,
      },
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_UNVERIFIED',
    );
  });

  test('Android REASON_UNKNOWN is not verified process death', () async {
    await expectInvalidLiveness(
      <String, Object?>{
        'alive': false,
        'pid': 4242,
        'processName': 'com.example.finance:platform_candidate_worker',
        'exitReasonCode': 0,
      },
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_UNVERIFIED',
    );
  });

  test('alive process cannot carry historical exit reason', () async {
    await expectInvalidLiveness(
      <String, Object?>{
        'alive': true,
        'pid': 4242,
        'processName': 'com.example.finance:platform_candidate_worker',
        'exitReasonCode': 9,
      },
      'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_RESPONSE_INVALID',
    );
  });

  test('result-file consumer rejects later SEARCH pages_read regression',
      () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(int pagesRead, int updatedAt) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'candidate_index': 1,
          'candidate_count': 1,
          'source_bytes_read': 1000,
          'source_bytes_total': 1000,
          'page_number': 50,
          'page_count': 100,
          'pages_read': pagesRead,
          'stage_elapsed_ms': 500,
          'updated_at_ms': updatedAt,
        };
    var observedSearchProgress = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(snapshot(13, firstAt)));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678'],
        onProgress: (progress) {
          if (progress.stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') {
            observedSearchProgress++;
            if (observedSearchProgress == 1) {
              resultFile.writeAsStringSync(jsonEncode(snapshot(12, firstAt + 1000)));
            }
          }
        },
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'search pages regression',
        contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGES_READ_REGRESSION'),
      )),
    );
    expect(observedSearchProgress, 1);
    expect(await resultFile.exists(), isTrue);
  });
  // Real result-file consumer and MethodChannel: reject a later SEARCH index
  // regression before emitting the forged native progress to the UI.
  test('result-file consumer rejects later SEARCH candidate index regression',
      () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(int index, int updatedAt) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'candidate_index': index,
          'candidate_count': 2,
          'source_bytes_read': 1000,
          'source_bytes_total': 1000,
          'page_number': 50,
          'page_count': 100,
          'pages_read': 13,
          'stage_elapsed_ms': 500,
          'updated_at_ms': updatedAt,
        };
    var observedSearchProgress = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(snapshot(2, firstAt)));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678', 'CD87654321'],
        onProgress: (progress) {
          if (progress.stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') {
            observedSearchProgress++;
            if (observedSearchProgress == 1) {
              resultFile.writeAsStringSync(jsonEncode(snapshot(1, firstAt + 1000)));
            }
          }
        },
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'search candidate index regression',
        contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CANDIDATE_INDEX_REGRESSION'),
      )),
    );
    expect(observedSearchProgress, 1);
    expect(await resultFile.exists(), isTrue);
  });


  // Real temporary result JSON + MethodChannel consumer: a changed page
  // count on the same verified SEARCH request must fail before UI progress.
  test('result-file consumer rejects changed SEARCH page count', () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(int pageCount, int updatedAt) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'candidate_index': 1,
          'candidate_count': 1,
          'source_bytes_read': 1000,
          'source_bytes_total': 1000,
          'page_number': 50,
          'page_count': pageCount,
          'pages_read': 13,
          'stage_elapsed_ms': 500,
          'updated_at_ms': updatedAt,
        };
    var observedSearchProgress = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(snapshot(100, firstAt)));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678'],
        onProgress: (progress) {
          if (progress.stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') {
            observedSearchProgress++;
            if (observedSearchProgress == 1) {
              resultFile.writeAsStringSync(
                jsonEncode(snapshot(101, firstAt + 1000)),
              );
            }
          }
        },
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'search page count changed',
        contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_COUNT_CHANGED'),
      )),
    );
    expect(observedSearchProgress, 1);
    expect(await resultFile.exists(), isTrue);
  });

  // Real result-file JSON and MethodChannel: reject forged SEARCH page identity
  // before sending a second, unverified progress event to the UI.
  test('consumer rejects changed SEARCH page with unchanged pages_read',
      () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(int pageNumber, int updatedAt) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': 'PLATFORM_RENDERER_CANDIDATE_SEARCH',
          'candidate_index': 1,
          'candidate_count': 1,
          'source_bytes_read': 1000,
          'source_bytes_total': 1000,
          'page_number': pageNumber,
          'page_count': 100,
          'pages_read': 13,
          'stage_elapsed_ms': 500,
          'updated_at_ms': updatedAt,
        };
    var observedSearchProgress = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(snapshot(50, firstAt)));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678'],
        onProgress: (progress) {
          if (progress.stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') {
            observedSearchProgress++;
            if (observedSearchProgress == 1) {
              resultFile.writeAsStringSync(
                jsonEncode(snapshot(51, firstAt + 1000)),
              );
            }
          }
        },
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'search page identity violation',
        contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_SEARCH_PAGE_IDENTITY_INVALID'),
      )),
    );
    expect(observedSearchProgress, 1);
    expect(await resultFile.exists(), isTrue);
  });


  // Real temporary JSON + MethodChannel consumer: an already-verified PID
  // cannot report fewer source bytes on a later Running snapshot. Fail before
  // the forged snapshot is emitted as fresh UI progress.
  test('result-file consumer rejects later source-byte rollback', () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(int bytesRead, int updatedAt) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': 'PLATFORM_SOURCE_SHA256',
          'candidate_index': 0,
          'candidate_count': 1,
          'source_bytes_read': bytesRead,
          'source_bytes_total': 1000,
          'page_number': 0,
          'page_count': 0,
          'pages_read': 0,
          'stage_elapsed_ms': 0,
          'updated_at_ms': updatedAt,
        };
    var observedHashProgress = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(snapshot(800, firstAt)));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678'],
        onProgress: (progress) {
          if (progress.stage == 'PLATFORM_SOURCE_SHA256') {
            observedHashProgress++;
            if (observedHashProgress == 1) {
              resultFile.writeAsStringSync(
                jsonEncode(snapshot(400, firstAt + 1000)),
              );
            }
          }
        },
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'source byte rollback',
        contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_SOURCE_BYTES_REGRESSION'),
      )),
    );
    expect(observedHashProgress, 1);
    expect(await resultFile.exists(), isTrue);
  });

  // Real temp-file/MethodChannel consumer: a PAGE_BEGIN emitted after
  // verified SEARCH cannot roll back distinct page reads, even with a later
  // timestamp and matching request/PID. Reject before displaying UI progress.
  test('result-file consumer rejects PAGE_BEGIN page-read rollback',
      () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(String stage, int pagesRead, int updatedAt) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': stage,
          'candidate_index': 1,
          'candidate_count': 1,
          'source_bytes_read': 1000,
          'source_bytes_total': 1000,
          'page_number': stage == 'PLATFORM_RENDERER_PAGE_BEGIN' ? 75 : 50,
          'page_count': 100,
          'pages_read': pagesRead,
          'stage_elapsed_ms': 500,
          'updated_at_ms': updatedAt,
        };
    var observedSearch = 0;
    var observedInvalidBegin = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(
          snapshot('PLATFORM_RENDERER_CANDIDATE_SEARCH', 13, firstAt),
        ));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678'],
        onProgress: (progress) {
          if (progress.stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') {
            observedSearch++;
            if (observedSearch == 1) {
              resultFile.writeAsStringSync(jsonEncode(
                snapshot('PLATFORM_RENDERER_PAGE_BEGIN', 0, firstAt + 1000),
              ));
            }
          } else if (progress.stage == 'PLATFORM_RENDERER_PAGE_BEGIN') {
            observedInvalidBegin++;
          }
        },
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'PAGE_BEGIN page-read rollback',
        contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_BEGIN_PAGES_READ_MISMATCH'),
      )),
    );
    expect(observedSearch, 1);
    expect(observedInvalidBegin, 0);
    expect(await resultFile.exists(), isTrue);
  });

  // Native overwrites a single result JSON faster than the 50ms Dart poll.
  // Observe SEARCH(13), then write PAGE_BEGIN(13), SEARCH(14),
  // PAGE_BEGIN(14), SEARCH(15), PAGE_BEGIN(15) before the next poll.
  // A valid sampled PAGE_BEGIN(15) must not be rejected as a forged jump.
  test('result-file consumer accepts skipped SEARCH before PAGE_BEGIN',
      () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(
      String stage, int pagesRead, int pageNumber, int updatedAt,
    ) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': stage,
          'candidate_index': 1,
          'candidate_count': 1,
          'source_bytes_read': 1000,
          'source_bytes_total': 1000,
          'page_number': pageNumber,
          'page_count': 100,
          'pages_read': pagesRead,
          'stage_elapsed_ms': 500,
          'updated_at_ms': updatedAt,
        };
    final cancellation = CloudAwardCandidateLookupCancellation();
    var observedSearch = 0;
    var observedBegin = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(snapshot(
          'PLATFORM_RENDERER_CANDIDATE_SEARCH', 13, 50, firstAt,
        )));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookupWith(cancellation, onProgress: (progress) {
        if (progress.stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') {
          observedSearch++;
          if (observedSearch == 1) {
            for (final sample in <(String, int, int, int)>[
              ('PLATFORM_RENDERER_PAGE_BEGIN', 13, 55, 10),
              ('PLATFORM_RENDERER_CANDIDATE_SEARCH', 14, 60, 16),
              ('PLATFORM_RENDERER_PAGE_BEGIN', 14, 65, 24),
              ('PLATFORM_RENDERER_CANDIDATE_SEARCH', 15, 70, 30),
              ('PLATFORM_RENDERER_PAGE_BEGIN', 15, 75, 45),
            ]) {
              resultFile.writeAsStringSync(jsonEncode(snapshot(
                sample.$1, sample.$2, sample.$3, firstAt + sample.$4,
              )));
            }
          }
        } else if (progress.stage == 'PLATFORM_RENDERER_PAGE_BEGIN') {
          observedBegin++;
          expect(progress.pagesRead, 15);
          expect(progress.pageNumber, 75);
          cancellation.cancel(); // Stop without synthesizing COMPLETE/negative.
        }
      }).timeout(const Duration(seconds: 5)),
      throwsA(isA<CloudAwardCandidateLookupCancelled>()),
    );
    expect(observedSearch, 1);
    expect(observedBegin, 1);
    expect(await resultFile.exists(), isTrue);
  });

  // Real temporary result JSON and MethodChannel consumer: native OPEN_WAIT
  // can finish writing after SEARCH because interrupt() does not join the
  // heartbeat thread. Reject the stale snapshot before UI progress.
  test('result-file consumer rejects OPEN_WAIT after verified SEARCH',
      () async {
    final firstAt = DateTime.now()
        .subtract(const Duration(seconds: 2))
        .millisecondsSinceEpoch;
    Map<String, Object?> snapshot(String stage, int updatedAt) =>
        <String, Object?>{
          'request_id': 'req-test',
          'status': 'running',
          'engine': 'android-platform-pdfrenderer-candidate-search',
          'worker_pid': 4242,
          'stage': stage,
          'candidate_index':
              stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH' ? 1 : 0,
          'candidate_count': 1,
          'source_bytes_read': 1000,
          'source_bytes_total': 1000,
          'page_number':
              stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH' ? 50 : 0,
          'page_count':
              stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH' ? 100 : 0,
          'pages_read':
              stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH' ? 13 : 0,
          'stage_elapsed_ms': 500,
          'updated_at_ms': updatedAt,
        };
    var observedSearchProgress = 0;
    var observedOpeningProgress = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startPlatformCandidateWorker') {
        await resultFile.writeAsString(jsonEncode(
          snapshot('PLATFORM_RENDERER_CANDIDATE_SEARCH', firstAt),
        ));
        return <String, Object?>{
          'requestId': 'req-test',
          'resultPath': resultFile.path,
        };
      }
      fail('Unexpected native method: ${call.method}');
    });
    await expectLater(
      lookup.findMatchesCrashIsolatedForTesting(
        artifact: artifact,
        candidateInvoiceNumbers: const <String>['AB12345678'],
        onProgress: (progress) {
          if (progress.stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') {
            observedSearchProgress++;
            if (observedSearchProgress == 1) {
              resultFile.writeAsStringSync(jsonEncode(
                snapshot('PLATFORM_RENDERER_OPEN_WAIT', firstAt + 1000),
              ));
            }
          } else if (progress.stage == 'PLATFORM_RENDERER_OPEN_WAIT') {
            observedOpeningProgress++;
          }
        },
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'stale native opening stage',
        contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_REGRESSION'),
      )),
    );
    expect(observedSearchProgress, 1);
    expect(observedOpeningProgress, 0);
    expect(await resultFile.exists(), isTrue);
  });

  // The native worker reports PAGE_BEGIN before adding the last distinct page.
  // Exercise real temporary JSON polling through the MethodChannel consumer:
  // pre-read pageCount-1 is valid, but pageCount is impossible and fail-closed.
  test('result-file PAGE_BEGIN rejects already-read full page count',
      () async {
    for (final pagesRead in <int>[99, 100]) {
      final cancellation = CloudAwardCandidateLookupCancellation();
      var observedBegin = 0;
      final snapshot = <String, Object?>{
        'request_id': 'req-test',
        'status': 'running',
        'engine': 'android-platform-pdfrenderer-candidate-search',
        'worker_pid': 4242,
        'stage': 'PLATFORM_RENDERER_PAGE_BEGIN',
        'candidate_index': 1,
        'candidate_count': 1,
        'source_bytes_read': 1000,
        'source_bytes_total': 1000,
        'page_number': 100,
        'page_count': 100,
        'pages_read': pagesRead,
        'stage_elapsed_ms': 500,
        'updated_at_ms': DateTime.now()
            .subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startPlatformCandidateWorker') {
          await resultFile.writeAsString(jsonEncode(snapshot));
          return <String, Object?>{
            'requestId': 'req-test',
            'resultPath': resultFile.path,
          };
        }
        fail('Unexpected native method: ${call.method}');
      });
      final pending = lookupWith(cancellation, onProgress: (progress) {
        observedBegin++;
        expect(progress.stage, 'PLATFORM_RENDERER_PAGE_BEGIN');
        cancellation.cancel();
      }).timeout(const Duration(seconds: 5));
      if (pagesRead == 99) {
        await expectLater(
          pending,
          throwsA(isA<CloudAwardCandidateLookupCancelled>()),
        );
        expect(observedBegin, 1);
      } else {
        await expectLater(
          pending,
          throwsA(isA<StateError>().having(
            (error) => error.toString(),
            'impossible PAGE_BEGIN pre-read cardinality',
            contains('CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID'),
          )),
        );
        expect(observedBegin, 0);
      }
      expect(await resultFile.exists(), isTrue);
    }
  });

}
