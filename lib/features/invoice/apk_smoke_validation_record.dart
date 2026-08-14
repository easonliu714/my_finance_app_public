enum ApkSmokeValidationResult {
  pass,
  warning,
  fail,
  skipped,
}

enum ApkSmokeValidationArea {
  myPage,
  aiModelSettings,
  imageStagingPreview,
  apkValidationChecklist,
}

class ApkSmokeValidationRecord {
  const ApkSmokeValidationRecord({
    required this.id,
    required this.area,
    required this.title,
    required this.result,
    required this.required,
    this.deviceLabel,
    this.note,
    this.checkedAt,
  });

  final String id;
  final ApkSmokeValidationArea area;
  final String title;
  final ApkSmokeValidationResult result;
  final bool required;
  final String? deviceLabel;
  final String? note;
  final DateTime? checkedAt;

  bool get blocksRelease => required && result == ApkSmokeValidationResult.fail;
  bool get needsReview => result == ApkSmokeValidationResult.warning || result == ApkSmokeValidationResult.fail;
  bool get isChecked => result != ApkSmokeValidationResult.skipped;
}

class ApkSmokeValidationSummary {
  const ApkSmokeValidationSummary({
    this.records = defaultRecords,
  });

  final List<ApkSmokeValidationRecord> records;

  static const List<ApkSmokeValidationRecord> defaultRecords = <ApkSmokeValidationRecord>[
    ApkSmokeValidationRecord(
      id: 'my-page-visible',
      area: ApkSmokeValidationArea.myPage,
      title: '我的頁可開啟',
      result: ApkSmokeValidationResult.skipped,
      required: true,
    ),
    ApkSmokeValidationRecord(
      id: 'ai-model-settings-visible',
      area: ApkSmokeValidationArea.aiModelSettings,
      title: 'AI 模型設定可見',
      result: ApkSmokeValidationResult.skipped,
      required: true,
    ),
    ApkSmokeValidationRecord(
      id: 'image-staging-preview-visible',
      area: ApkSmokeValidationArea.imageStagingPreview,
      title: '影像輔助記帳可見',
      result: ApkSmokeValidationResult.skipped,
      required: true,
    ),
    ApkSmokeValidationRecord(
      id: 'apk-validation-checklist-visible',
      area: ApkSmokeValidationArea.apkValidationChecklist,
      title: 'APK 欄位驗證清單可見',
      result: ApkSmokeValidationResult.skipped,
      required: true,
    ),
  ];

  int get passCount => records.where((record) => record.result == ApkSmokeValidationResult.pass).length;
  int get warningCount => records.where((record) => record.result == ApkSmokeValidationResult.warning).length;
  int get failCount => records.where((record) => record.result == ApkSmokeValidationResult.fail).length;
  int get skippedCount => records.where((record) => record.result == ApkSmokeValidationResult.skipped).length;
  int get blockedCount => records.where((record) => record.blocksRelease).length;
  bool get canRelease => blockedCount == 0;

  ApkSmokeValidationSummary copyWith({
    List<ApkSmokeValidationRecord>? records,
  }) {
    return ApkSmokeValidationSummary(records: records ?? this.records);
  }
}

class ApkSmokeValidationCopy {
  const ApkSmokeValidationCopy._();

  static const String title = 'APK 實機 Smoke 驗證紀錄';
  static const String ready = '必要 smoke 驗證未失敗，可繼續下一步 release gate。';
  static const String blocked = '仍有必要 smoke 驗證失敗，暫不可進入 release gate。';
}
