class GeminiKeyGroup {
  const GeminiKeyGroup({required this.alias, required this.apiKeys});

  final String alias;
  final List<String> apiKeys;

  bool get isEmpty => apiKeys.isEmpty;
}

/// Runtime credential router.
///
/// The historical class name is retained for source compatibility, but the
/// production contract is now a flat ordered API-key pool. Each key becomes an
/// anonymous runtime slot (`KEY_1`, `KEY_2`, ...). The UI never asks users to
/// model Google Project/quota groups.
class GeminiKeyGroupRouter {
  const GeminiKeyGroupRouter(this.groups);

  final List<GeminiKeyGroup> groups;

  factory GeminiKeyGroupRouter.fromApiKeys(List<String> apiKeys) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in apiKeys) {
      final key = raw.trim();
      if (key.isNotEmpty && seen.add(key)) normalized.add(key);
    }
    return GeminiKeyGroupRouter(
      List<GeminiKeyGroup>.unmodifiable(<GeminiKeyGroup>[
        for (var index = 0; index < normalized.length; index++)
          GeminiKeyGroup(
            alias: _alias(index),
            apiKeys: <String>[normalized[index]],
          ),
      ]),
    );
  }

  /// Legacy adapter only. Any historical grouped credentials are flattened
  /// back into the same ordered key pool instead of preserving UI grouping.
  factory GeminiKeyGroupRouter.fromGroups(List<GeminiKeyGroup> groups) {
    return GeminiKeyGroupRouter.fromApiKeys(<String>[
      for (final group in groups) ...group.apiKeys,
    ]);
  }

  List<GeminiKeyGroup> get healthyGroups =>
      List<GeminiKeyGroup>.unmodifiable(groups.where((group) => !group.isEmpty));

  static String _alias(int index) => 'KEY_${index + 1}';
}
