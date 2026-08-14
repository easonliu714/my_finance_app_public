class GeminiModelSettings {
  const GeminiModelSettings({
    this.availableModels = defaultModels,
    this.selectedModelId = defaultModelId,
  });

  static const String defaultModelId = 'gemini-flash-latest';

  static const List<GeminiModelOption> defaultModels = <GeminiModelOption>[
    GeminiModelOption(id: 'gemini-flash-latest', label: 'Gemini Flash latest'),
    GeminiModelOption(id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash'),
    GeminiModelOption(id: 'gemini-2.0-flash', label: 'Gemini 2.0 Flash'),
  ];

  final List<GeminiModelOption> availableModels;
  final String selectedModelId;

  GeminiModelOption get selectedModel => availableModels.firstWhere(
        (model) => model.id == selectedModelId,
        orElse: () => availableModels.first,
      );

  GeminiModelSettings copyWith({
    List<GeminiModelOption>? availableModels,
    String? selectedModelId,
  }) {
    return GeminiModelSettings(
      availableModels: availableModels ?? this.availableModels,
      selectedModelId: selectedModelId ?? this.selectedModelId,
    );
  }
}

class GeminiModelOption {
  const GeminiModelOption({
    required this.id,
    required this.label,
    this.supportsVision = true,
  });

  final String id;
  final String label;
  final bool supportsVision;
}

class GeminiSettingsCopy {
  const GeminiSettingsCopy._();

  static const String title = 'Gemini API 設定';
  static const String subtitle = '用於商品拍照辨識、發票影像辨識與參考價格建議。';
  static const String safeMasking = '輸入後只顯示遮蔽內容，不在畫面明碼顯示。';
  static const String multipleInput = '可一次貼上多組，使用逗號分隔。';
  static const String validation = '後續會提供有效性測試、模型選擇與額度用完自動切換。';
  static const String applicationHelp = '請到 Google AI Studio 建立 Gemini API Key。';
}
