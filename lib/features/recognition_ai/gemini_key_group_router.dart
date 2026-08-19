class GeminiKeyGroup {
  const GeminiKeyGroup({required this.alias, required this.apiKeys});

  final String alias;
  final List<String> apiKeys;

  bool get isEmpty => apiKeys.isEmpty;
}

class GeminiKeyGroupRouter {
  const GeminiKeyGroupRouter(this.groups);

  final List<GeminiKeyGroup> groups;

  /// Legacy flat keys do not prove independent Gemini quota boundaries.
  /// Gemini quotas are project-scoped, so they stay in one conservative group.
  factory GeminiKeyGroupRouter.fromApiKeys(List<String> apiKeys) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in apiKeys) {
      final key = raw.trim();
      if (key.isNotEmpty && seen.add(key)) normalized.add(key);
    }
    if (normalized.isEmpty) {
      return const GeminiKeyGroupRouter(<GeminiKeyGroup>[]);
    }
    return GeminiKeyGroupRouter(
      <GeminiKeyGroup>[
        GeminiKeyGroup(
          alias: 'LEGACY_GROUP',
          apiKeys: List<String>.unmodifiable(normalized),
        ),
      ],
    );
  }

  factory GeminiKeyGroupRouter.fromGroups(List<GeminiKeyGroup> groups) {
    final result = <GeminiKeyGroup>[];
    final seenKeys = <String>{};
    for (var index = 0; index < groups.length; index++) {
      final source = groups[index];
      final keys = source.apiKeys
          .map((key) => key.trim())
          .where((key) => key.isNotEmpty && seenKeys.add(key))
          .toList(growable: false);
      if (keys.isEmpty) continue;
      final alias = source.alias.trim().isEmpty ? _alias(index) : source.alias.trim();
      result.add(
        GeminiKeyGroup(
          alias: alias,
          apiKeys: List<String>.unmodifiable(keys),
        ),
      );
    }
    return GeminiKeyGroupRouter(List<GeminiKeyGroup>.unmodifiable(result));
  }

  List<GeminiKeyGroup> get healthyGroups =>
      List<GeminiKeyGroup>.unmodifiable(groups.where((group) => !group.isEmpty));

  static String _alias(int index) {
    final code = 65 + index;
    if (code <= 90) return 'GROUP_${String.fromCharCode(code)}';
    return 'GROUP_${index + 1}';
  }
}
