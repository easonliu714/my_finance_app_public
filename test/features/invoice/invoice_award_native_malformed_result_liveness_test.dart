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
        return <String, Object?>{
          'alive': alive,
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
}
