class BackupNotificationSettings {
  const BackupNotificationSettings({
    required this.enabled,
    required this.permissionStatus,
    required this.updatedAt,
  });

  final bool enabled;
  final BackupNotificationPermissionStatus permissionStatus;
  final DateTime? updatedAt;

  factory BackupNotificationSettings.defaults() {
    return const BackupNotificationSettings(
      enabled: false,
      permissionStatus: BackupNotificationPermissionStatus.notRequested,
      updatedAt: null,
    );
  }

  bool get isReady => enabled && permissionStatus == BackupNotificationPermissionStatus.granted;

  BackupNotificationSettings copyWith({
    bool? enabled,
    BackupNotificationPermissionStatus? permissionStatus,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return BackupNotificationSettings(
      enabled: enabled ?? this.enabled,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
    );
  }
}

enum BackupNotificationPermissionStatus {
  notRequested('尚未要求權限'),
  granted('已允許'),
  denied('已拒絕'),
  unsupported('裝置不支援');

  const BackupNotificationPermissionStatus(this.label);

  final String label;
}
