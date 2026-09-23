import 'invoice_award_official_dataset.dart';

class InvoiceAwardSelectablePeriod {
  const InvoiceAwardSelectablePeriod({
    required this.period,
    required this.drawYear,
    required this.drawMonth,
    required this.drawDay,
    required this.redemptionStartYear,
    required this.redemptionStartMonth,
    required this.redemptionStartDay,
    required this.redemptionEndYear,
    required this.redemptionEndMonth,
    required this.redemptionEndDay,
  });

  final OfficialInvoiceAwardPeriod period;
  final int drawYear;
  final int drawMonth;
  final int drawDay;
  final int redemptionStartYear;
  final int redemptionStartMonth;
  final int redemptionStartDay;
  final int redemptionEndYear;
  final int redemptionEndMonth;
  final int redemptionEndDay;

  DateTime get drawDate => DateTime(drawYear, drawMonth, drawDay);
  DateTime get redemptionStart =>
      DateTime(redemptionStartYear, redemptionStartMonth, redemptionStartDay);
  DateTime get redemptionEnd =>
      DateTime(redemptionEndYear, redemptionEndMonth, redemptionEndDay, 23, 59, 59);

  String get candidateAwardPeriodLabel =>
      '${period.rocYear}/${period.endMonth.toString().padLeft(2, '0')}';

  String get periodLabel =>
      '${period.rocYear}年'
      '${period.startMonth.toString().padLeft(2, '0')}-'
      '${period.endMonth.toString().padLeft(2, '0')}月';

  bool isDrawnAt(DateTime now) => !now.isBefore(drawDate);
  bool isExpiredAt(DateTime now) => now.isAfter(redemptionEnd);
  bool canCheckAt(DateTime now) => isDrawnAt(now) && !isExpiredAt(now);

  bool isRedeemableAt(DateTime now) =>
      !now.isBefore(redemptionStart) && !now.isAfter(redemptionEnd);

  String statusLabel(DateTime now) {
    if (!isDrawnAt(now)) return '尚未開獎（${_date(drawDate)}）';
    if (isExpiredAt(now)) return '已逾兌獎期限';
    if (!isRedeemableAt(now)) {
      return '已開獎，兌獎尚未開始（${_date(redemptionStart)} 起）';
    }
    return '兌獎期間內（至 ${_date(redemptionEnd)}）';
  }

  String menuLabel(DateTime now) => '$periodLabel · ${statusLabel(now)}';

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class InvoiceAwardRecentPeriodCatalog {
  const InvoiceAwardRecentPeriodCatalog._();

  static const period1150708 = InvoiceAwardSelectablePeriod(
    period: OfficialInvoiceAwardPeriod(rocYear: 115, startMonth: 7, endMonth: 8),
    drawYear: 2026,
    drawMonth: 9,
    drawDay: 25,
    redemptionStartYear: 2026,
    redemptionStartMonth: 10,
    redemptionStartDay: 6,
    redemptionEndYear: 2027,
    redemptionEndMonth: 1,
    redemptionEndDay: 5,
  );

  static const period1150506 = InvoiceAwardSelectablePeriod(
    period: OfficialInvoiceAwardPeriod(rocYear: 115, startMonth: 5, endMonth: 6),
    drawYear: 2026,
    drawMonth: 7,
    drawDay: 25,
    redemptionStartYear: 2026,
    redemptionStartMonth: 8,
    redemptionStartDay: 6,
    redemptionEndYear: 2026,
    redemptionEndMonth: 11,
    redemptionEndDay: 5,
  );

  static const _periods = <InvoiceAwardSelectablePeriod>[
    period1150708,
    period1150506,
  ];

  static List<InvoiceAwardSelectablePeriod> visibleAt(DateTime now) =>
      List<InvoiceAwardSelectablePeriod>.unmodifiable(
        _periods.where((item) => !item.isExpiredAt(now)),
      );

  static InvoiceAwardSelectablePeriod defaultAt(DateTime now) {
    final visible = visibleAt(now);
    for (final item in visible) {
      if (item.canCheckAt(now)) return item;
    }
    if (visible.isEmpty) {
      throw StateError('No supported invoice award period remains available');
    }
    return visible.first;
  }

  static bool usesPreviousPublication(
    InvoiceAwardSelectablePeriod selected,
    DateTime now,
  ) {
    for (final item in _periods) {
      if (item.canCheckAt(now)) return item.period.id != selected.period.id;
    }
    return false;
  }
}
