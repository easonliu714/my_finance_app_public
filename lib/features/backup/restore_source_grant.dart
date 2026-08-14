class RestoreSourceGrant {
  const RestoreSourceGrant({
    required this.uri,
    required this.displayName,
    required this.grantedAt,
    this.sourceKind = RestoreSourceKind.documentFile,
    this.persisted = true,
    this.pathBacked = true,
  });

  final String uri;
  final String displayName;
  final DateTime grantedAt;
  final RestoreSourceKind sourceKind;
  final bool persisted;
  final bool pathBacked;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'uri': uri,
      'display_name': displayName,
      'granted_at': grantedAt.toIso8601String(),
      'source_kind': sourceKind.name,
      'persisted': persisted ? '1' : '0',
      'path_backed': pathBacked ? '1' : '0',
    };
  }

  factory RestoreSourceGrant.fromMap(Map<String, Object?> map) {
    return RestoreSourceGrant(
      uri: map['uri']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? '',
      grantedAt: DateTime.tryParse(map['granted_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sourceKind: RestoreSourceKind.values.firstWhere(
        (kind) => kind.name == map['source_kind']?.toString(),
        orElse: () => RestoreSourceKind.documentFile,
      ),
      persisted: _boolValue(map['persisted'], fallback: true),
      pathBacked: _boolValue(map['path_backed'], fallback: true),
    );
  }
}

enum RestoreSourceKind { documentFile, directory, fallbackDirectory }

bool _boolValue(Object? value, {required bool fallback}) {
  if (value == null) return fallback;
  final text = value.toString().toLowerCase();
  if (text == '1' || text == 'true') return true;
  if (text == '0' || text == 'false') return false;
  return fallback;
}
