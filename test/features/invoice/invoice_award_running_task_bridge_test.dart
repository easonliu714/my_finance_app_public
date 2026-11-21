import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_cloud_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_eligibility_confirmation.dart';
import 'package:my_finance_app/features/invoice/invoice_award_running_task_bridge.dart';

void main() {
  InvoiceAwardRunningTaskSnapshot progress(String period, String stage) =>
      InvoiceAwardRunningTaskSnapshot(
        periodId: period,
        status: '一般獎已驗證',
        cloudStatus: stage,
        scanStatus: '一般獎中獎 1 筆；雲端尚未完成',
      );

  test('route reentry subscribes to the same running progress', () {
    final bridge = InvoiceAwardRunningTaskBridge();
    final seen = <String>[];
    expect(bridge.begin('115-07-08'), isTrue);
    final generation = bridge.generation;
    void oldRoute() => seen.add('old:${bridge.snapshotFor('115-07-08')?.cloudStatus}');
    bridge.addListener(oldRoute);
    bridge.publish(generation, progress('115-07-08', 'PLATFORM_SOURCE_SHA256'));
    bridge.removeListener(oldRoute); // Navigator pop / disposed State
    void newRoute() => seen.add('new:${bridge.snapshotFor('115-07-08')?.cloudStatus}');
    bridge.addListener(newRoute); // Navigator push / fresh State
    expect(bridge.activeFor('115-07-08'), isTrue);
    expect(bridge.snapshotFor('115-07-08')!.cloudStatus,
        'PLATFORM_SOURCE_SHA256');
    bridge.publish(generation, progress('115-07-08', 'PLATFORM_RENDERER_OPEN_WAIT'));
    expect(seen, <String>[
      'old:PLATFORM_SOURCE_SHA256',
      'new:PLATFORM_RENDERER_OPEN_WAIT',
    ]);
    bridge.finish(generation, '115-07-08');
    expect(bridge.active, isFalse);
    expect(bridge.snapshotFor('115-07-08')!.cloudStatus,
        'PLATFORM_RENDERER_OPEN_WAIT');
    bridge.dispose();
  });

  test('single flight blocks a second authorized task', () {
    final bridge = InvoiceAwardRunningTaskBridge();
    expect(bridge.begin('115-07-08'), isTrue);
    expect(bridge.begin('115-05-06'), isFalse);
    expect(bridge.periodId, '115-07-08');
    bridge.dispose();
  });

  test('period mismatches and stale generation cannot override result', () {
    final bridge = InvoiceAwardRunningTaskBridge();
    expect(bridge.begin('115-07-08'), isTrue);
    final first = bridge.generation;
    bridge.publish(first, progress('115-05-06', 'FORGED_PERIOD'));
    expect(bridge.snapshotFor('115-07-08'), isNull);
    bridge.publish(first, progress('115-07-08', 'REAL_STAGE'));
    bridge.finish(first, '115-05-06'); // wrong terminal identity
    expect(bridge.active, isTrue);
    bridge.finish(first, '115-07-08');
    expect(bridge.begin('115-05-06'), isTrue);
    bridge.publish(first, progress('115-05-06', 'STALE_RESULT'));
    expect(bridge.snapshotFor('115-05-06'), isNull);
    expect(bridge.snapshotFor('115-07-08'), isNull);
    bridge.dispose();
  });


  test('Owner C reentry drops stale 500 WIN and never promotes global NOT_WIN', () {
    const period = '115-07-08';
    final candidate = ExistingInvoiceAwardCandidate(
      transactionId: 'read-only-tx',
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime.utc(2026, 8, 10),
      awardPeriod: '115/08',
      identitySource: ExistingInvoiceAwardIdentitySource.cloudMetadata,
      sourceProvenance: 'isolated-test',
      cloudEligibility: ExistingInvoiceAwardCloudEligibility.eligible,
    );
    ExistingInvoiceAwardCloudEvaluation evaluation(
      String? tier,
      ExistingInvoiceAwardCloudEvaluationStatus status,
    ) => ExistingInvoiceAwardCloudEvaluation(
      candidate: candidate,
      status: status,
      missingTierCodes: const <String>{},
      matchedTierCodes: tier == null ? const <String>{} : <String>{tier},
      selectedTierCode: tier,
      grossAmount: tier == 'cloud-500' ? 500 : 800,
      pdfSha256: 'a' * 64,
    );
    InvoiceAwardCloudEligibilityConfirmation confirmation(String tier) =>
        InvoiceAwardCloudEligibilityConfirmation(
          periodId: period,
          candidateKey: candidate.dedupeKey,
          candidateSourceProvenance: 'isolated-test',
          tierCode: tier,
          grossAmount: tier == 'cloud-500' ? 500 : 800,
          officialPdfSha256: 'a' * 64,
          decision: InvoiceAwardCloudEligibilityUserDecision.eligible,
          confirmedAtUtc: DateTime.utc(2026, 9, 25),
        );
    final old = InvoiceAwardRunningTaskSnapshot(
      periodId: period,
      status: '一般獎已驗證',
      cloudStatus: '舊版雲端四獎別全部驗證',
      scanStatus: '舊版 500 元中獎',
      cloudDiagnosticStatus: '舊版 PDF 診斷',
      tierSummaries: const <String, String>{
        'cloud-500': 'WIN',
        'cloud-800': '其他獎別結果',
      },
      activeTierCode: 'cloud-500',
      cloudComplete: true,
      candidates: <ExistingInvoiceAwardCandidate>[candidate],
      cloudEvaluations: <ExistingInvoiceAwardCloudEvaluation>[
        evaluation('cloud-500', ExistingInvoiceAwardCloudEvaluationStatus.matchedEligible),
        evaluation('cloud-800', ExistingInvoiceAwardCloudEvaluationStatus.matchedEligible),
        evaluation(null, ExistingInvoiceAwardCloudEvaluationStatus.notMatched),
      ],
      confirmations: <String, InvoiceAwardCloudEligibilityConfirmation>{
        'legacy-500': confirmation('cloud-500'),
        'other-800': confirmation('cloud-800'),
      },
    );
    final safe = old.withoutDeferredCloud500Authority();
    expect(safe.status, '一般獎已驗證');
    expect(safe.candidates, hasLength(1));
    expect(safe.cloudComplete, isFalse);
    expect(safe.cloudStatus, contains('暫緩'));
    expect(safe.scanStatus, isNot(contains('中獎')));
    expect(safe.cloudDiagnosticStatus, isEmpty);
    expect(safe.activeTierCode, isNull);
    expect(safe.tierSummaries.keys, isNot(contains('cloud-500')));
    expect(safe.tierSummaries['cloud-800'], '其他獎別結果');
    expect(safe.confirmations.keys, contains('other-800'));
    expect(safe.confirmations.keys, isNot(contains('legacy-500')));
    expect(safe.cloudEvaluations[0].selectedTierCode, isNull);
    expect(safe.cloudEvaluations[0].grossAmount, 0);
    expect(safe.cloudEvaluations[0].status,
        ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete);
    expect(safe.cloudEvaluations[1].selectedTierCode, 'cloud-800');
    expect(safe.cloudEvaluations[1].grossAmount, 800);
    expect(safe.cloudEvaluations[2].status,
        ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete);
    for (final value in safe.cloudEvaluations) {
      expect(value.hasCompleteAuthority, isFalse);
      expect(value.missingTierCodes, contains('cloud-500'));
      expect(value.matchedTierCodes, isNot(contains('cloud-500')));
    }
    // The pre-deferral record is retained, not mutated or deleted.
    expect(old.cloudComplete, isTrue);
    expect(old.cloudEvaluations.first.selectedTierCode, 'cloud-500');
    expect(old.confirmations.keys, contains('legacy-500'));
  });

  test('new Android process has no trustworthy running task', () {
    final previousProcess = InvoiceAwardRunningTaskBridge();
    expect(previousProcess.begin('115-07-08'), isTrue);
    previousProcess.publish(
      previousProcess.generation,
      progress('115-07-08', 'PLATFORM_RENDERER_OPEN_WAIT'),
    );
    final restartedProcess = InvoiceAwardRunningTaskBridge();
    expect(restartedProcess.active, isFalse);
    expect(restartedProcess.snapshotFor('115-07-08'), isNull);
    previousProcess.dispose();
    restartedProcess.dispose();
  });
}
