import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'taiwan_business_calendar_official_116_stage.dart';
import 'taiwan_business_calendar_package.dart';
import 'taiwan_business_calendar_package_service.dart';

/// B2.12: deterministic first-install package for the one SHA-pinned 116 CSV.
///
/// This is an explicit-consent entry point, not a scheduler or a downloader.
/// Revision sequence 1 is a LOCAL baseline ordinal, not a DGPA revision ID.
/// The 2026-05-21 date refers to DGPA's 116 calendar announcement, NOT a
/// per-resource CSV revision timestamp. Later official changes require a new
/// independently authenticated pin and reviewed higher sequence.
class TaiwanBusinessCalendarPinned116Installer {
  const TaiwanBusinessCalendarPinned116Installer();

  static const sourceUrl =
      'https://www.dgpa.gov.tw/FileConversion?filename=dgpa%2Ffiles%2F202607%2Ff538b1ff-ba60-4c63-9477-10db8e6612d1.csv&name=116%E5%B9%B4%E4%B8%AD%E8%8F%AF%E6%B0%91%E5%9C%8B%E6%94%BF%E5%BA%9C%E8%A1%8C%E6%94%BF%E6%A9%9F%E9%97%9C%E8%BE%A6%E5%85%AC%E6%97%A5%E6%9B%86%E8%A1%A8_utf8bom.csv&nfix=';
  static const calendarAnnouncementUrl =
      'https://www.dgpa.gov.tw/information?fr=ev22548C0701M03&pid=12983&uid=82';
  static const sourceRevision =
      'DGPA-116-2027-PIN-e30df188649bf5347db3ec43fa989af2cc8d93d793fbe5c9891601e6cce4acf3';
  static const localBaselineSequence = 1;
  static const calendarAnnouncementDate = '2026-05-21';
  // Immutable manifest-generation time: a retry must have the SAME digest.
  // This is not a claimed CSV publication or update timestamp.
  static const pinnedManifestGeneratedAt = '2026-11-03T11:15:00Z';

  Future<TaiwanBusinessCalendarYearPackage> prepare(
    Uint8List originalCsv,
  ) async {
    // Verify exact bytes AND all 365 day rows before constructing metadata.
    final verified =
        await const TaiwanBusinessCalendarOfficial116Stage().verify(originalCsv);
    return const TaiwanBusinessCalendarPackageCodec().build(
      sourceYear: TaiwanBusinessCalendarOfficial116Stage.sourceYear,
      sourceRevision: sourceRevision,
      revisionSequence: localBaselineSequence,
      sourceUrl: sourceUrl,
      sourcePublishedAt: calendarAnnouncementDate,
      generatedAt: pinnedManifestGeneratedAt,
      days: verified.days,
    );
  }

  Future<CalendarPackageInstallResult> install(
    Database db,
    Uint8List originalCsv, {
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw const CalendarPackageConflictException(
        'Explicit calendar installation confirmation is required.',
      );
    }
    // No production DB write can precede source identity and full-year parse.
    final package = await prepare(originalCsv);
    // Existing atomic transaction owns downgrade, collision and rollback.
    return const TaiwanBusinessCalendarPackageService().install(db, package);
  }
}
