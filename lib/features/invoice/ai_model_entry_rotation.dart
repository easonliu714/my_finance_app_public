enum AiModelEntryStatus {
  unknown,
  usable,
  rejected,
  quotaExhausted,
  disabled,
}

class AiModelEntry {
  const AiModelEntry({
    required this.id,
    required this.maskedLabel,
    this.status = AiModelEntryStatus.unknown,
    this.lastCheckedAt,
  });

  final String id;
  final String maskedLabel;
  final AiModelEntryStatus status;
  final DateTime? lastCheckedAt;

  bool get canBeUsed => status == AiModelEntryStatus.unknown || status == AiModelEntryStatus.usable;
  bool get shouldRotateAway => status == AiModelEntryStatus.rejected || status == AiModelEntryStatus.quotaExhausted || status == AiModelEntryStatus.disabled;

  AiModelEntry copyWith({
    String? id,
    String? maskedLabel,
    AiModelEntryStatus? status,
    DateTime? lastCheckedAt,
  }) {
    return AiModelEntry(
      id: id ?? this.id,
      maskedLabel: maskedLabel ?? this.maskedLabel,
      status: status ?? this.status,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

class AiModelEntryRotationState {
  const AiModelEntryRotationState({
    this.entries = const <AiModelEntry>[],
    this.lastSuccessfulEntryId,
  });

  final List<AiModelEntry> entries;
  final String? lastSuccessfulEntryId;

  AiModelEntry? get activeEntry => AiModelEntryRotationService.selectUsableEntry(
        entries,
        preferredEntryId: lastSuccessfulEntryId,
      );

  AiModelEntryRotationState copyWith({
    List<AiModelEntry>? entries,
    String? lastSuccessfulEntryId,
  }) {
    return AiModelEntryRotationState(
      entries: entries ?? this.entries,
      lastSuccessfulEntryId: lastSuccessfulEntryId ?? this.lastSuccessfulEntryId,
    );
  }
}

class AiModelEntryRotationService {
  const AiModelEntryRotationService();

  static AiModelEntry? selectUsableEntry(
    List<AiModelEntry> entries, {
    String? preferredEntryId,
  }) {
    if (entries.isEmpty) return null;
    if (preferredEntryId != null) {
      for (final entry in entries) {
        if (entry.id == preferredEntryId && entry.canBeUsed) return entry;
      }
    }
    for (final entry in entries) {
      if (entry.canBeUsed) return entry;
    }
    return null;
  }

  static AiModelEntryRotationState markEntryStatus({
    required AiModelEntryRotationState state,
    required String entryId,
    required AiModelEntryStatus status,
    required DateTime checkedAt,
  }) {
    final updatedEntries = state.entries
        .map(
          (entry) => entry.id == entryId ? entry.copyWith(status: status, lastCheckedAt: checkedAt) : entry,
        )
        .toList(growable: false);
    return state.copyWith(
      entries: updatedEntries,
      lastSuccessfulEntryId: status == AiModelEntryStatus.usable ? entryId : state.lastSuccessfulEntryId,
    );
  }
}
