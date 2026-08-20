import 'dart:convert';

/// Legacy compatibility shape retained only so P4.19.1 can safely decode
/// settings written by the short-lived project/group UI. New settings are
/// always stored as one flat ordered API-key pool.
class GeminiInvoiceKeyGroup {
  const GeminiInvoiceKeyGroup({
    required this.alias,
    required this.apiKeys,
  });

  final String alias;
  final List<String> apiKeys;

  bool get isEmpty => apiKeys.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'alias': alias,
        'apiKeys': apiKeys,
      };

  factory GeminiInvoiceKeyGroup.fromJson(Map<String, Object?> values) {
    final alias = values['alias']?.toString().trim() ?? '';
    final keys = GeminiInvoiceSettings.parseApiKeys(
      (values['apiKeys'] as List?)?.join('\n') ?? '',
    );
    return GeminiInvoiceKeyGroup(alias: alias, apiKeys: keys);
  }
}

class GeminiInvoiceSettings {
  const GeminiInvoiceSettings({
    this.apiKeys = const <String>[],
    this.keyGroups = const <GeminiInvoiceKeyGroup>[],
    this.model = defaultModel,
    this.experimentalInvoiceVisionEnabled = false,
    this.autoReviewLowConfidenceEnabled = false,
    this.debugToolsEnabled = true,
  });

  static const String defaultModel = 'gemini-3.6-flash';
  static const String legacyGroupAlias = 'LEGACY_GROUP';

  /// Canonical ordered credential pool used by production runtime.
  final List<String> apiKeys;

  /// Legacy decode-only field. New saves write an empty list and runtime never
  /// requires users to understand quota/project grouping.
  final List<GeminiInvoiceKeyGroup> keyGroups;
  final String model;
  final bool experimentalInvoiceVisionEnabled;
  final bool autoReviewLowConfidenceEnabled;
  final bool debugToolsEnabled;

  bool get hasApiKey => effectiveApiKeys.isNotEmpty;

  /// Flattens both the canonical list and any legacy v3 grouped payload so an
  /// upgrade never asks the user to re-enter keys.
  List<String> get effectiveApiKeys {
    final result = <String>[];
    final seen = <String>{};
    void addAll(Iterable<String> values) {
      for (final raw in values) {
        final key = raw.trim();
        if (key.isNotEmpty && seen.add(key)) result.add(key);
      }
    }

    addAll(apiKeys);
    for (final group in keyGroups) {
      addAll(group.apiKeys);
    }
    return List<String>.unmodifiable(result);
  }

  /// Compatibility projection only. Each key is represented as one anonymous
  /// runtime slot; this is not a user-configurable quota/project group.
  List<GeminiInvoiceKeyGroup> get effectiveKeyGroups =>
      List<GeminiInvoiceKeyGroup>.unmodifiable(<GeminiInvoiceKeyGroup>[
        for (var index = 0; index < effectiveApiKeys.length; index++)
          GeminiInvoiceKeyGroup(
            alias: _generatedKeyAlias(index),
            apiKeys: <String>[effectiveApiKeys[index]],
          ),
      ]);

  String get keyGroupInputText => effectiveApiKeys.join('，');

  GeminiInvoiceSettings copyWith({
    List<String>? apiKeys,
    List<GeminiInvoiceKeyGroup>? keyGroups,
    String? model,
    bool? experimentalInvoiceVisionEnabled,
    bool? autoReviewLowConfidenceEnabled,
    bool? debugToolsEnabled,
  }) {
    return GeminiInvoiceSettings(
      apiKeys: apiKeys ?? this.apiKeys,
      keyGroups: keyGroups ?? this.keyGroups,
      model: model ?? this.model,
      experimentalInvoiceVisionEnabled:
          experimentalInvoiceVisionEnabled ?? this.experimentalInvoiceVisionEnabled,
      autoReviewLowConfidenceEnabled:
          autoReviewLowConfidenceEnabled ?? this.autoReviewLowConfidenceEnabled,
      debugToolsEnabled: debugToolsEnabled ?? this.debugToolsEnabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 4,
        'apiKeys': effectiveApiKeys,
        // Kept as an explicit empty array so rollback/diagnostic decoders can
        // distinguish the new flat-key authority from a truncated payload.
        'keyGroups': const <Object?>[],
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
      final schemaVersion = switch (values['schemaVersion']) {
        final int value => value,
        final Object value => int.tryParse(value.toString()) ?? 1,
        null => 1,
      };
      final flatKeys = parseApiKeys(
        (values['apiKeys'] as List?)?.join('\n') ?? '',
      );
      final migratedKeys = <String>[...flatKeys];
      final rawGroups = values['keyGroups'];
      if (rawGroups is List) {
        for (final raw in rawGroups) {
          if (raw is! Map) continue;
          final group = GeminiInvoiceKeyGroup.fromJson(
            Map<String, Object?>.from(raw.cast<String, Object?>()),
          );
          migratedKeys.addAll(group.apiKeys);
        }
      }
      final keys = parseApiKeys(migratedKeys.join('\n'));
      final featureEnabled = values['experimentalInvoiceVisionEnabled'] == true;
      final savedAutoReview = values['autoReviewLowConfidenceEnabled'] == true;

      // P4.19.1 schema <=3 required an explicit Save after toggling the switch.
      // Real-device evidence proved that the UI could look enabled while the
      // persisted flag stayed false. When AI review was already enabled, the
      // v4 migration restores the intended Local-low-confidence auto escalation.
      final autoReviewEnabled = schemaVersion <= 3 && featureEnabled
          ? true
          : savedAutoReview;

      return GeminiInvoiceSettings(
        apiKeys: keys,
        keyGroups: const <GeminiInvoiceKeyGroup>[],
        model: _normalizedModel(values['model']?.toString()),
        experimentalInvoiceVisionEnabled: featureEnabled,
        autoReviewLowConfidenceEnabled: autoReviewEnabled,
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

  /// Deprecated compatibility parser. All keys now belong to one user-facing
  /// pool; the returned singleton slots exist only for legacy source callers.
  static List<GeminiInvoiceKeyGroup> parseKeyGroups(String raw) {
    final keys = parseApiKeys(raw);
    return List<GeminiInvoiceKeyGroup>.unmodifiable(<GeminiInvoiceKeyGroup>[
      for (var index = 0; index < keys.length; index++)
        GeminiInvoiceKeyGroup(
          alias: _generatedKeyAlias(index),
          apiKeys: <String>[keys[index]],
        ),
    ]);
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

  static String _generatedKeyAlias(int index) => 'KEY_${index + 1}';
}
