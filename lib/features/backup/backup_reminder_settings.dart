class BackupReminderSettings {
  const BackupReminderSettings({
    required this.enabled,
    required this.intervalDays,
    this.lastBackupAt,
    this.automaticBackupEnabled = false,
    this.networkUsageAllowed = false,
    this.cloudBackupHandoffEnabled = false,
  });

  static const int defaultIntervalDays = 7;
  static const int minIntervalDays = 1;
  static const int maxIntervalDays = 365;

  factory BackupReminderSettings.defaults() {
    return const BackupReminderSettings(enabled: true, intervalDays: defaultIntervalDays);
  }

  factory BackupReminderSettings.fromMap(Map<String, Object?> map) {
    return BackupReminderSettings(
      enabled: _readBool(map['enabled'], fallback: true),
      intervalDays: clampIntervalDays(_readInt(map['interval_days'], fallback: defaultIntervalDays)),
      lastBackupAt: _readDateTime(map['last_backup_at']),
      automaticBackupEnabled: _readBool(map['automatic_backup_enabled'], fallback: false),
      networkUsageAllowed: _readBool(map['network_usage_allowed'], fallback: false),
      cloudBackupHandoffEnabled: _readBool(map['cloud_backup_handoff_enabled'], fallback: false),
    );
  }

  final bool enabled;
  final int intervalDays;
  final DateTime? lastBackupAt;
  final bool automaticBackupEnabled;
  final bool networkUsageAllowed;
  final bool cloudBackupHandoffEnabled;

  DateTime? nextReminderAt() {
    final backupAt = lastBackupAt;
    if (!enabled || backupAt == null) return null;
    return backupAt.add(Duration(days: intervalDays));
  }

  bool isReminderDue(DateTime now) {
    final next = nextReminderAt();
    if (next == null) return false;
    return !now.isBefore(next);
  }

  BackupReminderSettings copyWith({
    bool? enabled,
    int? intervalDays,
    DateTime? lastBackupAt,
    bool clearLastBackupAt = false,
    bool? automaticBackupEnabled,
    bool? networkUsageAllowed,
    bool? cloudBackupHandoffEnabled,
  }) {
    return BackupReminderSettings(
      enabled: enabled ?? this.enabled,
      intervalDays: clampIntervalDays(intervalDays ?? this.intervalDays),
      lastBackupAt: clearLastBackupAt ? null : (lastBackupAt ?? this.lastBackupAt),
      automaticBackupEnabled: automaticBackupEnabled ?? this.automaticBackupEnabled,
      networkUsageAllowed: networkUsageAllowed ?? this.networkUsageAllowed,
      cloudBackupHandoffEnabled: cloudBackupHandoffEnabled ?? this.cloudBackupHandoffEnabled,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'enabled': enabled ? 1 : 0,
      'interval_days': intervalDays,
      'last_backup_at': lastBackupAt?.toIso8601String(),
      'automatic_backup_enabled': automaticBackupEnabled ? 1 : 0,
      'network_usage_allowed': networkUsageAllowed ? 1 : 0,
      'cloud_backup_handoff_enabled': cloudBackupHandoffEnabled ? 1 : 0,
    };
  }

  static int clampIntervalDays(int value) {
    if (value < minIntervalDays) return minIntervalDays;
    if (value > maxIntervalDays) return maxIntervalDays;
    return value;
  }

  static bool _readBool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') return true;
      if (normalized == 'false' || normalized == '0' || normalized == 'no') return false;
    }
    return fallback;
  }

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) return DateTime.tryParse(value.trim());
    return null;
  }
}
