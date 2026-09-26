/// Pure, local domain contract for official uniform-invoice award redemption.
///
/// This file deliberately performs no network I/O, scheduling, notification,
/// persistence, payout, or formal accounting write.
class InvoiceAwardRedemptionWindow {
  const InvoiceAwardRedemptionWindow({
    required this.periodId,
    required this.drawDate,
    required this.redemptionStart,
    required this.redemptionEnd,
  });

  final String periodId;
  final DateTime drawDate;
  final DateTime redemptionStart;
  final DateTime redemptionEnd;

  bool get hasValidUtcBounds =>
      periodId.trim().isNotEmpty &&
      drawDate.isUtc &&
      redemptionStart.isUtc &&
      redemptionEnd.isUtc &&
      redemptionStart.isAfter(drawDate) &&
      !redemptionEnd.isBefore(redemptionStart);

  bool isMatchableAt(DateTime instant) {
    if (!hasValidUtcBounds || !instant.isUtc) return false;
    return !instant.isBefore(drawDate);
  }

  bool isRedeemableAt(DateTime instant) {
    if (!hasValidUtcBounds || !instant.isUtc) return false;
    return !instant.isBefore(redemptionStart) &&
        !instant.isAfter(redemptionEnd);
  }

  bool get canCreateFormalTransaction => false;
}

/// Selects validated local periods without conflating matching and redemption.
class InvoiceAwardPeriodSelection {
  const InvoiceAwardPeriodSelection._({
    required this.currentMatchable,
    required this.stillRedeemable,
  });

  final InvoiceAwardRedemptionWindow? currentMatchable;
  final List<InvoiceAwardRedemptionWindow> stillRedeemable;

  factory InvoiceAwardPeriodSelection.select({
    required Iterable<InvoiceAwardRedemptionWindow> windows,
    required DateTime now,
  }) {
    if (!now.isUtc) {
      return const InvoiceAwardPeriodSelection._(
        currentMatchable: null,
        stillRedeemable: <InvoiceAwardRedemptionWindow>[],
      );
    }

    final valid = windows.where((window) => window.hasValidUtcBounds).toList()
      ..sort((left, right) => right.drawDate.compareTo(left.drawDate));

    InvoiceAwardRedemptionWindow? current;
    for (final window in valid) {
      if (window.isMatchableAt(now)) {
        current = window;
        break;
      }
    }

    final redeemable = valid
        .where((window) => window.isRedeemableAt(now))
        .toList(growable: false);

    return InvoiceAwardPeriodSelection._(
      currentMatchable: current,
      stillRedeemable: List<InvoiceAwardRedemptionWindow>.unmodifiable(
        redeemable,
      ),
    );
  }
}
