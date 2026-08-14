import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini_model_settings.dart';

void main() {
  test('uses Flash latest as default model', () {
    const settings = GeminiModelSettings();

    expect(settings.selectedModelId, GeminiModelSettings.defaultModelId);
    expect(settings.selectedModel.id, 'gemini-flash-latest');
    expect(settings.selectedModel.supportsVision, isTrue);
  });

  test('can select an available model', () {
    const settings = GeminiModelSettings(selectedModelId: 'gemini-2.5-flash');

    expect(settings.selectedModel.id, 'gemini-2.5-flash');
    expect(settings.selectedModel.label, 'Gemini 2.5 Flash');
  });

  test('falls back to first model when selected model is unavailable', () {
    const settings = GeminiModelSettings(selectedModelId: 'missing-model');

    expect(settings.selectedModel.id, GeminiModelSettings.defaultModelId);
  });

  test('copyWith updates model without changing available models', () {
    const settings = GeminiModelSettings();
    final updated = settings.copyWith(selectedModelId: 'gemini-2.0-flash');

    expect(updated.selectedModel.id, 'gemini-2.0-flash');
    expect(updated.availableModels, settings.availableModels);
  });

  test('copy text documents the settings page shell', () {
    expect(GeminiSettingsCopy.title, 'Gemini API 設定');
    expect(GeminiSettingsCopy.safeMasking, contains('遮蔽'));
    expect(GeminiSettingsCopy.multipleInput, contains('逗號'));
    expect(GeminiSettingsCopy.validation, contains('模型選擇'));
  });
}
