import 'dart:convert';

class GeminiInvoiceSettings {
  const GeminiInvoiceSettings({
    this.apiKeys = const <String>[],
    this.model = defaultModel,
    this.experimentalInvoiceVisionEnabled = false,
    this.autoReviewLowConfidenceEnabled = false,
    this.debugToolsEnabled = true,
  });

  static const String defaultModel = 'gemini-3.6-flash';

  final List<String> apiKeys;
  final String model;
  final bool experimentalInvoiceVisionEnabled;
  final bool autoReviewLowConfidenceEnabled;
  final bool debugToolsEnabled;

  bool get hasApiKey => apiKeys.isNotEmpty;

  GeminiInvoiceSettings copyWith({
    List<String>? apiKeys,
    String? model,
    bool? experimentalInvoiceVisionEnabled,
    bool? autoReviewLowConfidenceEnabled,
    bool? debugToolsEnabled,
  }) {
    return GeminiInvoiceSettings(
      apiKeys: apiKeys ?? this.apiKeys,
      model: model ?? this.model,
      experimentalInvoiceVisionEnabled:
          experimentalInvoiceVisionEnabled ?? this.experimentalInvoiceVisionEnabled,
      autoReviewLowConfidenceEnabled:
          autoReviewLowConfidenceEnabled ?? this.autoReviewLowConfidenceEnabled,
      debugToolsEnabled: debugToolsEnabled ?? this.debugToolsEnabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 2,
        'apiKeys': apiKeys,
        'model': model,
        'experimentalInvoiceVisionEnabled': experimentalInvoiceVisionEnabled,
        'autoReviewLowConfidenceEnabled': autoReviewLowConfidenceEnabled,
        'debugToolsEnabled': debugToolsEnabled,
      };

  String encode() => jsonEncode(toJson());

  factory GeminiInvoiceSettings.decode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return const GeminiInvoiceSettings();
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const GeminiInvoiceSettings();
      final values = Map<String, Object?>.from(decoded.cast<String, Object?>());
      return GeminiInvoiceSettings(
        apiKeys: parseApiKeys((values['apiKeys'] as List?)?.join('\n') ?? ''),
        model: _normalizedModel(values['model']?.toString()),
        experimentalInvoiceVisionEnabled:
            values['experimentalInvoiceVisionEnabled'] == true,
        autoReviewLowConfidenceEnabled:
            values['autoReviewLowConfidenceEnabled'] == true,
        debugToolsEnabled: values['debugToolsEnabled'] != false,
      );
    } catch (_) {
      return const GeminiInvoiceSettings();
    }
  }

  static List<String> parseApiKeys(String raw) {
    final values = raw
        .split(RegExp(r'[\s,，、;；]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      if (seen.add(value)) result.add(value);
    }
    return List<String>.unmodifiable(result);
  }

  static String maskApiKey(String value) {
    final key = value.trim();
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  static String _normalizedModel(String? value) {
    final normalized = value?.trim().replaceFirst(RegExp(r'^models/'), '');
    return normalized?.isNotEmpty == true ? normalized! : defaultModel;
  }
}