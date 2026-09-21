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
  DateTime? nextTarget({
    required DateTime nowLocal,
    required bool generalDatasetPromoted,
    required bool cloudExclusiveDatasetPromoted,
  }) {
    if (!permitsAutomaticNetworkFetch ||
        (generalDatasetPromoted && cloudExclusiveDatasetPromoted)) {
      return null;
    }

    final publicationDay = _publicationDayFor(nowLocal);
    final firstTarget = DateTime(
      publicationDay.year,
      publicationDay.month,
      publicationDay.day,
      firstAttemptHour,
    );
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
    final publicationDay = _publicationDayFor(nowLocal);
    final firstTarget = DateTime(
      publicationDay.year,
      publicationDay.month,
      publicationDay.day,
      firstAttemptHour,
    );
    if (nowLocal.isBefore(firstTarget)) return false;
    if (lastAttemptLocal == null || lastAttemptLocal.isBefore(firstTarget)) {
      return true;
    }
    return nowLocal.difference(lastAttemptLocal) >= retryInterval;
  }

  DateTime _publicationDayFor(DateTime nowLocal) {
    var year = nowLocal.year;
    var month = nowLocal.month;
    if (month.isEven) month -= 1;
    var candidate = DateTime(year, month, 25);
    if (nowLocal.isBefore(candidate)) {
      month -= 2;
      if (month < 1) {
        month += 12;
        year -= 1;
      }
      candidate = DateTime(year, month, 25);
    }
    return candidate;
  }

  bool get canCreateFormalTransaction => false;
}
