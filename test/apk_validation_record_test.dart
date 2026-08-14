import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/apk_validation_record.dart';

void main() {
  test('pending APK validation record is not ready', () {
    const record = ApkValidationRecord.pending;

    expect(record.outcome, ApkValidationOutcome.pending);
    expect(record.hasAllRequiredChecks, isFalse);
    expect(record.isReadyForVisibleEntryReview, isFalse);
    expect(record.blocksVisibleEntryEnablement, isTrue);
    expect(record.canEnableGateAutomatically, isFalse);
    expect(record.canCreateFinalRecordAutomatically, isFalse);
  });

  test('passed APK validation record is ready for manual review', () {
    const record = ApkValidationRecord(
      phase: 'P4.10.20',
      buildVersion: '4.10.20+303',
      outcome: ApkValidationOutcome.passed,
      checks: <ApkValidationCheckResult>[
        ApkValidationCheckResult(id: 'install_and_open', passed: true),
        ApkValidationCheckResult(id: 'hidden_route_absent_from_navigation', passed: true),
        ApkValidationCheckResult(id: 'actions_remain_disabled', passed: true),
      ],
    );

    expect(record.hasAllRequiredChecks, isTrue);
    expect(record.isReadyForVisibleEntryReview, isTrue);
    expect(record.blocksVisibleEntryEnablement, isFalse);
    expect(record.requiresManualReview, isTrue);
    expect(record.canEnableGateAutomatically, isFalse);
  });

  test('failed APK validation record is not ready', () {
    const record = ApkValidationRecord(
      phase: 'P4.10.20',
      buildVersion: '4.10.20+303',
      outcome: ApkValidationOutcome.failed,
      checks: <ApkValidationCheckResult>[
        ApkValidationCheckResult(id: 'install_and_open', passed: true),
        ApkValidationCheckResult(id: 'hidden_route_absent_from_navigation', passed: false),
      ],
    );

    expect(record.hasAllRequiredChecks, isFalse);
    expect(record.isReadyForVisibleEntryReview, isFalse);
    expect(record.blocksVisibleEntryEnablement, isTrue);
    expect(record.canCreateFinalRecordAutomatically, isFalse);
  });

  test('APK validation record copy documents boundary', () {
    expect(ApkValidationRecordCopy.templateOnly, contains('template'));
    expect(ApkValidationRecordCopy.validationRequired, contains('Manual APK validation'));
  });
}
