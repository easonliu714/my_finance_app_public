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

}
