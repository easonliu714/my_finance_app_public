import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/apk_validation_execution_request.dart';
import 'package:my_finance_app/features/invoice/apk_validation_record.dart';

void main() {
  test('pending APK validation execution request blocks visible entry enablement', () {
    const request = ApkValidationExecutionRequest.pending;

    expect(request.phase, 'P4.10.21');
    expect(request.requestedBuildVersion, '4.10.21+304');
    expect(request.status, ApkValidationExecutionStatus.pending);
    expect(request.hasRequiredEvidencePlan, isTrue);
    expect(request.isReadyForVisibleEntryReview, isFalse);
    expect(request.blocksVisibleEntryEnablement, isTrue);
    expect(request.canEnableGateAutomatically, isFalse);
    expect(request.canCreateFinalRecordAutomatically, isFalse);
  });

  test('completed request with passed record is ready for manual review', () {
    const passedRecord = ApkValidationRecord(
      phase: 'P4.10.21',
      buildVersion: '4.10.21+304',
      outcome: ApkValidationOutcome.passed,
      checks: <ApkValidationCheckResult>[
        ApkValidationCheckResult(id: 'install_and_open', passed: true),
        ApkValidationCheckResult(id: 'hidden_route_absent_from_navigation', passed: true),
        ApkValidationCheckResult(id: 'actions_remain_disabled', passed: true),
      ],
    );
    final request = ApkValidationExecutionRequest(
      phase: 'P4.10.21',
      requestedBuildVersion: '4.10.21+304',
      status: ApkValidationExecutionStatus.completed,
      validationItemIds: ApkValidationExecutionRequest.pending.validationItemIds,
      evidenceRequirements: ApkValidationExecutionRequest.pending.evidenceRequirements,
      validationRecord: passedRecord,
    );

    expect(request.hasPassedValidationRecord, isTrue);
    expect(request.isReadyForVisibleEntryReview, isTrue);
    expect(request.blocksVisibleEntryEnablement, isFalse);
    expect(request.requiresManualReview, isTrue);
    expect(request.canEnableGateAutomatically, isFalse);
  });

  test('completed request without passed record still blocks enablement', () {
    final request = ApkValidationExecutionRequest(
      phase: 'P4.10.21',
      requestedBuildVersion: '4.10.21+304',
      status: ApkValidationExecutionStatus.completed,
      validationItemIds: ApkValidationExecutionRequest.pending.validationItemIds,
      evidenceRequirements: ApkValidationExecutionRequest.pending.evidenceRequirements,
    );

    expect(request.hasPassedValidationRecord, isFalse);
    expect(request.isReadyForVisibleEntryReview, isFalse);
    expect(request.blocksVisibleEntryEnablement, isTrue);
  });

  test('APK validation execution request copy documents boundary', () {
    expect(ApkValidationExecutionRequestCopy.requestOnly, contains('request'));
    expect(ApkValidationExecutionRequestCopy.passedRecordRequired, contains('passed APK validation record'));
  });
}
