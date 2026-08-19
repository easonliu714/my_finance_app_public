import '../invoice/gemini/gemini_model_catalog_client.dart';

class GeminiFlashModelRouter {
  const GeminiFlashModelRouter();

  List<String> candidates({
    required String preferredModel,
    required List<GeminiModelDescriptor> catalog,
  }) {
    final preferred = _normalize(preferredModel);
    final available = <String, GeminiModelDescriptor>{
      for (final model in catalog) _normalize(model.id): model,
    };
    final result = <String>[];

    if (preferred.isNotEmpty && available.containsKey(preferred)) {
      result.add(preferred);
    }

    for (final model in catalog) {
      final id = _normalize(model.id);
      if (id.isEmpty || result.contains(id)) continue;
      if (!model.supportsGenerateContent) continue;
      if (!id.toLowerCase().contains('flash')) continue;
      result.add(id);
    }

    // If the provider catalog could not be loaded, preserve the user's current
    // configured model as the only candidate. We do not invent model IDs.
    if (catalog.isEmpty && preferred.isNotEmpty) result.add(preferred);

    return List<String>.unmodifiable(result);
  }

  bool isPreferredAvailable({
    required String preferredModel,
    required List<GeminiModelDescriptor> catalog,
  }) {
    final preferred = _normalize(preferredModel);
    return preferred.isNotEmpty &&
        catalog.any((model) => _normalize(model.id) == preferred);
  }

  String _normalize(String value) =>
      value.trim().replaceFirst(RegExp(r'^models/'), '');
}
