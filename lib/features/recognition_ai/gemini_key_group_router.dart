class GeminiKeyGroup {
  const GeminiKeyGroup({required this.alias, required this.apiKeys});

  final String alias;
  final List<String> apiKeys;

  bool get isEmpty => apiKeys.isEmpty;
}

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

  List<GeminiKeyGroup> get healthyGroups =>
      List<GeminiKeyGroup>.unmodifiable(groups.where((group) => !group.isEmpty));

  static String _alias(int index) {
    final code = 65 + index;
    if (code <= 90) return 'GROUP_${String.fromCharCode(code)}';
    return 'GROUP_${index + 1}';
  }
}
