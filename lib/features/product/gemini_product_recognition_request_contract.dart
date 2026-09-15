import 'product_multi_item_transport_contract.dart';

/// Builds the additive Gemini request contract for optional multi-item evidence.
///
/// This object is intentionally limited to request construction. It does not
/// interpret recognition output, create master data, or authorize formal writes.
abstract final class GeminiProductRecognitionRequestContract {
  static Map<String, Object?> responseSchema(
    Map<String, Object?> legacySchema,
  ) {
    final legacyProperties = legacySchema['properties'];
    if (legacyProperties is! Map) {
      return Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(legacySchema),
      );
    }

    final properties = Map<String, Object?>.from(legacyProperties);
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      ...legacySchema,
      'properties': ProductMultiItemTransportContract.withOptionalLinesProperty(
        properties,
      ),
    });
  }

  static String prompt(String legacyPrompt) =>
      ProductMultiItemTransportContract.withPromptAddendum(legacyPrompt);
}
