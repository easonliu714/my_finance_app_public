import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/apk_smoke_validation_record.dart';

void main() {
  test('default smoke validation records start skipped and do not block release', () {
    const summary = ApkSmokeValidationSummary();

    expect(summary.records.length, 4);
    expect(summary.skippedCount, 4);
    expect(summary.passCount, 0);
    expect(summary.warningCount, 0);
    expect(summary.failCount, 0);
    expect(summary.blockedCount, 0);
    expect(summary.canRelease, isTrue);
    expect(summary.records.map((record) => record.id), contains('my-page-visible'));
    expect(summary.records.map((record) => record.id), contains('apk-validation-checklist-visible'));
  });

  test('required failed smoke record blocks release', () {
    const summary = ApkSmokeValidationSummary(
      records: <ApkSmokeValidationRecord>[
        ApkSmokeValidationRecord(
          id: 'required-fail',
          area: ApkSmokeValidationArea.myPage,
          title: '必要 smoke 失敗',
          result: ApkSmokeValidationResult.fail,
          required: true,
        ),
      ],
    );

    expect(summary.failCount, 1);
    expect(summary.blockedCount, 1);
    expect(summary.canRelease, isFalse);
    expect(summary.records.single.needsReview, isTrue);
    expect(summary.records.single.blocksRelease, isTrue);
  });

  test('optional failed smoke record needs review but does not block release', () {
    const record = ApkSmokeValidationRecord(
      id: 'optional-fail',
      area: ApkSmokeValidationArea.imageStagingPreview,
      title: '選用 smoke 失敗',
      result: ApkSmokeValidationResult.fail,
      required: false,
    );
    const summary = ApkSmokeValidationSummary(records: <ApkSmokeValidationRecord>[record]);

    expect(record.needsReview, isTrue);
    expect(record.blocksRelease, isFalse);
    expect(summary.canRelease, isTrue);
  });

  test('pass warning fail skipped counts are summarized', () {
    const summary = ApkSmokeValidationSummary(
      records: <ApkSmokeValidationRecord>[
        ApkSmokeValidationRecord(
          id: 'pass',
          area: ApkSmokeValidationArea.myPage,
          title: '通過',
          result: ApkSmokeValidationResult.pass,
          required: true,
        ),
        ApkSmokeValidationRecord(
          id: 'warning',
          area: ApkSmokeValidationArea.aiModelSettings,
          title: '警告',
          result: ApkSmokeValidationResult.warning,
          required: true,
        ),
        ApkSmokeValidationRecord(
          id: 'fail',
          area: ApkSmokeValidationArea.imageStagingPreview,
          title: '失敗',
          result: ApkSmokeValidationResult.fail,
          required: false,
        ),
        ApkSmokeValidationRecord(
          id: 'skipped',
          area: ApkSmokeValidationArea.apkValidationChecklist,
          title: '略過',
          result: ApkSmokeValidationResult.skipped,
          required: true,
        ),
      ],
    );

    expect(summary.passCount, 1);
    expect(summary.warningCount, 1);
    expect(summary.failCount, 1);
    expect(summary.skippedCount, 1);
    expect(summary.blockedCount, 0);
    expect(summary.canRelease, isTrue);
  });
}
