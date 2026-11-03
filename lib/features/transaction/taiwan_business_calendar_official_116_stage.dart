import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'taiwan_business_calendar_csv_import.dart';
import 'taiwan_business_calendar_package.dart';

/// B2.9: pinned 116/2027 official CSV identity plus strict complete-year parse.
/// This is staging evidence ONLY: publication/revision custody, explicit
/// installation consent and transactional production LKG remain separate HOLDs.
class TaiwanBusinessCalendarOfficial116Stage {
  const TaiwanBusinessCalendarOfficial116Stage();

  static const int sourceYear = 2027;
  static const int pinnedByteLength = 6511;
  static const int pinnedHolidayCount = 121;
  static const String pinnedSha256 =
      'e30df188649bf5347db3ec43fa989af2cc8d93d793fbe5c9891601e6cce4acf3';

  Future<TaiwanBusinessCalendarOfficial116StageResult> verify(
    Uint8List bytes,
  ) async {
    // Reject before allocating a parsed year or attempting any DB access.
    if (bytes.lengthInBytes != pinnedByteLength) {
      throw const TaiwanBusinessCalendarPackageException(
        'DGPA 116 official CSV byte length differs from the pinned source.');
    }
    final digest = await Sha256().hash(bytes);
    final actualSha256 = digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    if (actualSha256 != pinnedSha256) {
      throw const TaiwanBusinessCalendarPackageException(
        'DGPA 116 official CSV SHA-256 identity mismatch.');
    }
    final days = const TaiwanBusinessCalendarOfficialCsvCodec()
        .parseFullYear(bytes, sourceYear: sourceYear);
    final holidays = days.where((day) => !day.isBusinessDay).length;
    if (days.length != 365 || holidays != pinnedHolidayCount) {
      throw const TaiwanBusinessCalendarPackageException(
        'DGPA 116 verified source row/holiday count mismatch.');
    }
    return TaiwanBusinessCalendarOfficial116StageResult._(
      days: days,
      rawSha256: actualSha256,
      holidayCount: holidays,
    );
  }
}

class TaiwanBusinessCalendarOfficial116StageResult {
  const TaiwanBusinessCalendarOfficial116StageResult._({
    required this.days,
    required this.rawSha256,
    required this.holidayCount,
  });

  final List<TaiwanBusinessCalendarPackageDay> days;
  final String rawSha256;
  final int holidayCount;
  int get sourceYear => TaiwanBusinessCalendarOfficial116Stage.sourceYear;

  // Deliberately no install(), sourcePublishedAt or revisionSequence here.
  // A SHA match cannot authorize a production SQLite mutation.
}
