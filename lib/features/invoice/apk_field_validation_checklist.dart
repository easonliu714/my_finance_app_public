enum ApkFieldValidationStatus {
  pass,
  warning,
  fail,
  notApplicable,
}

enum ApkFieldValidationSeverity {
  required,
  recommended,
  optional,
}

class ApkFieldValidationItem {
  const ApkFieldValidationItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.severity,
  });

  final String id;
  final String title;
  final String description;
  final ApkFieldValidationStatus status;
  final ApkFieldValidationSeverity severity;

  bool get blocksRelease => severity == ApkFieldValidationSeverity.required && status == ApkFieldValidationStatus.fail;
  bool get needsReview => status == ApkFieldValidationStatus.warning || status == ApkFieldValidationStatus.fail;
}

class ApkFieldValidationChecklist {
  const ApkFieldValidationChecklist({
    this.items = defaultItems,
  });

  final List<ApkFieldValidationItem> items;

  static const List<ApkFieldValidationItem> defaultItems = <ApkFieldValidationItem>[
    ApkFieldValidationItem(
      id: 'ai-model-settings-visible',
      title: 'AI 模型設定可見',
      description: '我的頁應可看到 AI 模型設定卡片與目前模型。',
      status: ApkFieldValidationStatus.pass,
      severity: ApkFieldValidationSeverity.required,
    ),
    ApkFieldValidationItem(
      id: 'image-staging-shell-visible',
      title: '影像 staging preview 可見',
      description: '我的頁應可看到影像輔助記帳入口與待審核文案。',
      status: ApkFieldValidationStatus.pass,
      severity: ApkFieldValidationSeverity.required,
    ),
    ApkFieldValidationItem(
      id: 'camera-gallery-placeholder',
      title: '拍照與相簿仍為佔位入口',
      description: '本階段不可要求相機權限、不可開啟相簿、不可上傳影像。',
      status: ApkFieldValidationStatus.pass,
      severity: ApkFieldValidationSeverity.required,
    ),
    ApkFieldValidationItem(
      id: 'review-first-copy',
      title: '人工確認優先文案',
      description: '影像結果只進待審核清單，不可自動建立交易。',
      status: ApkFieldValidationStatus.pass,
      severity: ApkFieldValidationSeverity.required,
    ),
    ApkFieldValidationItem(
      id: 'device-smoke-test',
      title: '實機 smoke test',
      description: 'P4.8 後續需在 APK 實機確認我的頁、AI 模型設定與影像 staging preview 顯示。',
      status: ApkFieldValidationStatus.warning,
      severity: ApkFieldValidationSeverity.recommended,
    ),
  ];

  bool get canRelease => !items.any((item) => item.blocksRelease);
  int get requiredFailCount => items.where((item) => item.blocksRelease).length;
  int get warningCount => items.where((item) => item.status == ApkFieldValidationStatus.warning).length;
  int get passCount => items.where((item) => item.status == ApkFieldValidationStatus.pass).length;

  ApkFieldValidationChecklist copyWith({
    List<ApkFieldValidationItem>? items,
  }) {
    return ApkFieldValidationChecklist(items: items ?? this.items);
  }
}

class ApkFieldValidationCopy {
  const ApkFieldValidationCopy._();

  static const String title = 'APK 欄位驗證清單';
  static const String releaseBlocked = '仍有必要項目未通過，暫不可進入 APK release gate。';
  static const String releaseReady = '必要項目已通過，可進入下一步 APK 實機驗證。';
}
