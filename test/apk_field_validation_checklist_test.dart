import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/apk_field_validation_checklist.dart';

void main() {
  test('default checklist allows next APK validation step with warnings only', () {
    const checklist = ApkFieldValidationChecklist();

    expect(checklist.canRelease, isTrue);
    expect(checklist.requiredFailCount, 0);
    expect(checklist.warningCount, 1);
    expect(checklist.passCount, 4);
    expect(checklist.items.map((item) => item.id), contains('ai-model-settings-visible'));
    expect(checklist.items.map((item) => item.id), contains('image-staging-shell-visible'));
    expect(checklist.items.map((item) => item.id), contains('review-first-copy'));
  });

  test('required fail blocks release gate', () {
    const checklist = ApkFieldValidationChecklist(
      items: <ApkFieldValidationItem>[
        ApkFieldValidationItem(
          id: 'required-fail',
          title: '必要項目失敗',
          description: '必要欄位不可失敗。',
          status: ApkFieldValidationStatus.fail,
          severity: ApkFieldValidationSeverity.required,
        ),
        ApkFieldValidationItem(
          id: 'recommended-warning',
          title: '建議項目警告',
          description: '警告不阻擋 release gate。',
          status: ApkFieldValidationStatus.warning,
          severity: ApkFieldValidationSeverity.recommended,
        ),
      ],
    );

    expect(checklist.canRelease, isFalse);
    expect(checklist.requiredFailCount, 1);
    expect(checklist.warningCount, 1);
  });

  test('recommended fail needs review but does not block release gate', () {
    const item = ApkFieldValidationItem(
      id: 'recommended-fail',
      title: '建議項目失敗',
      description: '建議項目需檢查，但不阻擋 gate。',
      status: ApkFieldValidationStatus.fail,
      severity: ApkFieldValidationSeverity.recommended,
    );
    const checklist = ApkFieldValidationChecklist(items: <ApkFieldValidationItem>[item]);

    expect(item.needsReview, isTrue);
    expect(item.blocksRelease, isFalse);
    expect(checklist.canRelease, isTrue);
  });

  test('not applicable optional item does not need review', () {
    const item = ApkFieldValidationItem(
      id: 'optional-na',
      title: '選用項目',
      description: '本階段不適用。',
      status: ApkFieldValidationStatus.notApplicable,
      severity: ApkFieldValidationSeverity.optional,
    );

    expect(item.needsReview, isFalse);
    expect(item.blocksRelease, isFalse);
  });
}
