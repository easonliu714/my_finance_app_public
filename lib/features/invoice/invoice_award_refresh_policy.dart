/// Pure policy for Issue #13 award-number refresh timing.
///
/// No timer, background worker, notification, or network request is started by
/// this contract. Android execution remains best-effort; production adapters
/// must perform foreground catch-up when a due attempt was missed.
class InvoiceAwardRefreshPolicy {
  const InvoiceAwardRefreshPolicy({
    required this.automaticRefreshConsented,
    this.firstAttemptHour = 14,
    this.retryInterval = const Duration(minutes: 30),
  });

  final bool automaticRefreshConsented;
  final int firstAttemptHour;
  final Duration retryInterval;

  bool get isValid =>
      firstAttemptHour >= 0 &&
      firstAttemptHour <= 23 &&
      retryInterval >= const Duration(minutes: 1);

  /// Returns whether an automatic official-dataset network attempt is allowed.
  /// Opt-out is a hard zero-network boundary.
  bool get permitsAutomaticNetworkFetch =>
      isValid && automaticRefreshConsented;

  /// Odd-month 25th is the publication day. The first target is 14:00 local
  /// time, followed by approximately 30-minute best-effort retries until both
  /// general and cloud-exclusive datasets have been validated/promoted.
  ///
  /// Automatic retries are deliberately scoped to the current publication
  /// cycle. Before the current odd-month 25th at 14:00, no older cycle is
  /// resurrected: unchanged historical datasets are reused locally and the
  /// next automatic target is the upcoming publication attempt.
  DateTime? nextTarget({
    required DateTime nowLocal,
    required bool generalDatasetPromoted,
    required bool cloudExclusiveDatasetPromoted,
  }) {
    if (!permitsAutomaticNetworkFetch ||
        (generalDatasetPromoted && cloudExclusiveDatasetPromoted)) {
      return null;
    }

    final firstTarget = _currentCycleFirstTarget(nowLocal);
    if (nowLocal.isBefore(firstTarget)) return firstTarget;

    final elapsed = nowLocal.difference(firstTarget);
    final steps = elapsed.inMicroseconds ~/ retryInterval.inMicroseconds + 1;
    return firstTarget.add(retryInterval * steps);
  }

  /// True when foreground execution should catch up a missed target. Adapters
  /// should still re-check promotion state before any network request.
  bool foregroundCatchUpDue({
    required DateTime nowLocal,
    required DateTime? lastAttemptLocal,
    required bool generalDatasetPromoted,
    required bool cloudExclusiveDatasetPromoted,
  }) {
    if (!permitsAutomaticNetworkFetch ||
        (generalDatasetPromoted && cloudExclusiveDatasetPromoted)) {
      return false;
    }
    final firstTarget = _currentCycleFirstTarget(nowLocal);
    if (nowLocal.isBefore(firstTarget)) return false;
    if (lastAttemptLocal == null || lastAttemptLocal.isBefore(firstTarget)) {
      return true;
    }
    return nowLocal.difference(lastAttemptLocal) >= retryInterval;
  }

  DateTime _currentCycleFirstTarget(DateTime nowLocal) {
    final year = nowLocal.year;
    final month = nowLocal.month;

    // Even months belong to the next odd-month publication cycle. This avoids
    // resurrecting the previous odd month's retry loop after its publication
    // day has passed; validated historical datasets remain local evidence.
    if (month.isEven) {
      final nextOddMonth = month + 1;
      return DateTime(year, nextOddMonth, 25, firstAttemptHour);
    }

    return DateTime(year, month, 25, firstAttemptHour);
  }

  bool get canCreateFormalTransaction => false;
}
