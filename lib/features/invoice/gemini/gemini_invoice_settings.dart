import 'dart:convert';

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

  /// Flat credential list retained for source compatibility with P4.16-P4.19.
  /// Quota routing authority is [effectiveKeyGroups], not this list.
  final List<String> apiKeys;
  final List<GeminiInvoiceKeyGroup> keyGroups;
  final String model;
  final bool experimentalInvoiceVisionEnabled;
  final bool autoReviewLowConfidenceEnabled;
  final bool debugToolsEnabled;

  bool get hasApiKey => effectiveApiKeys.isNotEmpty;

  List<String> get effectiveApiKeys {
    final result = <String>[];
    final seen = <String>{};
    for (final group in effectiveKeyGroups) {
      for (final key in group.apiKeys) {
        if (seen.add(key)) result.add(key);
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// Legacy flat keys are conservatively treated as ONE quota boundary.
  /// Gemini rate limits are project-scoped, so separate groups must only be
  /// created from explicit user grouping rather than inferred from key count.
  List<GeminiInvoiceKeyGroup> get effectiveKeyGroups {
    final explicit = keyGroups
        .where((group) => !group.isEmpty)
        .map(
          (group) => GeminiInvoiceKeyGroup(
            alias: _safeAlias(group.alias, fallbackIndex: 0),
            apiKeys: parseApiKeys(group.apiKeys.join('\n')),
          ),
        )
        .where((group) => !group.isEmpty)
        .toList(growable: false);
    if (explicit.isNotEmpty) {
      return List<GeminiInvoiceKeyGroup>.unmodifiable(explicit);
    }
    final legacy = parseApiKeys(apiKeys.join('\n'));
    if (legacy.isEmpty) return const <GeminiInvoiceKeyGroup>[];
    return <GeminiInvoiceKeyGroup>[
      GeminiInvoiceKeyGroup(alias: legacyGroupAlias, apiKeys: legacy),
    ];
  }

  String get keyGroupInputText => effectiveKeyGroups
      .map((group) => group.apiKeys.join('，'))
      .join('\n');

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
        'schemaVersion': 3,
        // Keep the flattened field for backward-compatible diagnostics and
        // rollback decode. The authoritative quota topology is keyGroups.
        'apiKeys': effectiveApiKeys,
        'keyGroups': <Object?>[
          for (final group in effectiveKeyGroups) group.toJson(),
        ],
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
      final flatKeys = parseApiKeys(
        (values['apiKeys'] as List?)?.join('\n') ?? '',
      );
      final parsedGroups = <GeminiInvoiceKeyGroup>[];
      final rawGroups = values['keyGroups'];
      if (rawGroups is List) {
        for (final raw in rawGroups) {
          if (raw is! Map) continue;
          final group = GeminiInvoiceKeyGroup.fromJson(
            Map<String, Object?>.from(raw.cast<String, Object?>()),
          );
          if (group.isEmpty) continue;
          parsedGroups.add(
            GeminiInvoiceKeyGroup(
              alias: _safeAlias(
                group.alias,
                fallbackIndex: parsedGroups.length,
              ),
              apiKeys: group.apiKeys,
            ),
          );
        }
      }
      // v2 and earlier do not prove that keys belong to independent projects.
      // Preserve them as one legacy quota group rather than inventing groups.
      final groups = parsedGroups.isNotEmpty
          ? parsedGroups
          : flatKeys.isEmpty
              ? const <GeminiInvoiceKeyGroup>[]
              : <GeminiInvoiceKeyGroup>[
                  GeminiInvoiceKeyGroup(
                    alias: legacyGroupAlias,
                    apiKeys: flatKeys,
                  ),
                ];
      final flattened = <String>[
        for (final group in groups) ...group.apiKeys,
      ];
      return GeminiInvoiceSettings(
        apiKeys: parseApiKeys(flattened.join('\n')),
        keyGroups: List<GeminiInvoiceKeyGroup>.unmodifiable(groups),
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

  /// Parses the existing flat key syntax. New quota grouping is line-based and
  /// is handled by [parseKeyGroups].
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

  /// Each non-empty line is an explicit independent quota/project group.
  /// Keys on the same line are credentials for the same quota boundary.
  static List<GeminiInvoiceKeyGroup> parseKeyGroups(String raw) {
    final groups = <GeminiInvoiceKeyGroup>[];
    final seenKeys = <String>{};
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      final keys = parseApiKeys(line)
          .where((key) => seenKeys.add(key))
          .toList(growable: false);
      if (keys.isEmpty) continue;
      groups.add(
        GeminiInvoiceKeyGroup(
          alias: _generatedGroupAlias(groups.length),
          apiKeys: List<String>.unmodifiable(keys),
        ),
      );
    }
    return List<GeminiInvoiceKeyGroup>.unmodifiable(groups);
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

  static String _safeAlias(String value, {required int fallbackIndex}) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? _generatedGroupAlias(fallbackIndex) : normalized;
  }

  static String _generatedGroupAlias(int index) {
    final code = 65 + index;
    if (code <= 90) return 'GROUP_${String.fromCharCode(code)}';
    return 'GROUP_${index + 1}';
  }
}
