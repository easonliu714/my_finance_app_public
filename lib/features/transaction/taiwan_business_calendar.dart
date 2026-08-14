abstract interface class BusinessDayCalendar {
  bool isBusinessDay(DateTime value);

  void requireCoverage(DateTime value);
}

class BusinessCalendarCoverageException implements Exception {
  const BusinessCalendarCoverageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Taiwan business-day calendar used by debit-card settlement planning.
///
/// Saturdays, Sundays, national holidays, and officially announced substitute
/// holidays are non-business days. The bundled calendar is sourced from the
/// Directorate-General of Personnel Administration office calendars for 2026
/// and 2027. Unknown years fail closed instead of being treated as workdays.
class TaiwanBusinessCalendar implements BusinessDayCalendar {
  const TaiwanBusinessCalendar({
    required this.coverageStart,
    required this.coverageEnd,
    required this.nonBusinessDateKeys,
    required this.sourceRevision,
  });

  const TaiwanBusinessCalendar.bundled()
      : coverageStart = '2026-01-01',
        coverageEnd = '2027-12-31',
        nonBusinessDateKeys = _bundledWeekdayClosures,
        sourceRevision = 'DGPA-115-116';

  final String coverageStart;
  final String coverageEnd;
  final List<String> nonBusinessDateKeys;
  final String sourceRevision;

  @override
  void requireCoverage(DateTime value) {
    final key = dateKey(value);
    if (key.compareTo(coverageStart) < 0 || key.compareTo(coverageEnd) > 0) {
      throw BusinessCalendarCoverageException(
        'Taiwan business-calendar coverage $coverageStart..$coverageEnd '
        'does not include $key.',
      );
    }
  }

  @override
  bool isBusinessDay(DateTime value) {
    requireCoverage(value);
    if (value.weekday == DateTime.saturday ||
        value.weekday == DateTime.sunday) {
      return false;
    }
    return !nonBusinessDateKeys.contains(dateKey(value));
  }

  static String dateKey(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)}';
  }
}

const List<String> _bundledWeekdayClosures = <String>[
  // 2026 / ROC 115 DGPA office calendar.
  '2026-01-01',
  '2026-02-16',
  '2026-02-17',
  '2026-02-18',
  '2026-02-19',
  '2026-02-20',
  '2026-02-27',
  '2026-04-03',
  '2026-04-06',
  '2026-05-01',
  '2026-06-19',
  '2026-09-25',
  '2026-09-28',
  '2026-10-09',
  '2026-10-26',
  '2026-12-25',

  // 2027 / ROC 116 DGPA office calendar.
  '2027-01-01',
  '2027-02-04',
  '2027-02-05',
  '2027-02-08',
  '2027-02-09',
  '2027-02-10',
  '2027-03-01',
  '2027-04-05',
  '2027-04-06',
  '2027-04-30',
  '2027-06-09',
  '2027-09-15',
  '2027-09-28',
  '2027-10-11',
  '2027-10-25',
  '2027-12-24',
  '2027-12-31',
];
