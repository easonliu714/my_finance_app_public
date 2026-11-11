import 'package:sqflite/sqflite.dart';

import 'taiwan_business_calendar_package.dart';

enum CalendarPackageInstallDisposition { installed, unchanged }

class CalendarPackageConflictException implements Exception {
  const CalendarPackageConflictException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CalendarPackageInstallResult {
  const CalendarPackageInstallResult({
    required this.disposition,
    required this.year,
    required this.revision,
    required this.sequence,
    required this.digest,
    required this.rowCount,
  });
  final CalendarPackageInstallDisposition disposition;
  final int year;
  final String revision;
  final int sequence;
  final String digest;
  final int rowCount;
}

class CalendarPackageStatus {
  const CalendarPackageStatus({
    required this.year,
    required this.start,
    required this.end,
    required this.rowCount,
    required this.revision,
    required this.sequence,
    required this.digest,
    required this.sourceUrl,
    required this.importedAt,
    required this.isContiguous,
    this.hasCanonicalRowDigest = false,
  });
  final int year;
  final String start;
  final String end;
  final int rowCount;
  final String revision;
  final int sequence;
  final String digest;
  final String sourceUrl;
  final String importedAt;
  final bool isContiguous;
  // True only when persisted days were rebuilt and matched the canonical
  // package SHA-256. Legacy metadata without generated_at is structural-only.
  // This does not establish official publisher authenticity.
  final bool hasCanonicalRowDigest;
}


enum CalendarAnnualUpdateDecision {
  outsideDecember,
  currentYearNotVerified,
  beforeFirstBusinessDay,
  nextYearUntrusted,
  nextYearInstalled,
  checkedToday,
  checkOfficialSource,
}

class TaiwanBusinessCalendarPackageService {
  const TaiwanBusinessCalendarPackageService();

  static const tableName = 'taiwan_business_calendar_days';


  // B2.4: read-only foreground eligibility, never an authority to download,
  // install or infer holidays. Taiwan is UTC+08:00 with no DST.
  // A verified current-year package supplies the *actual* first December
  // business day; a weekend heuristic or incomplete legacy rows cannot.
  // The caller must persist lastCheckedAt after a real attempted check.
  Future<CalendarAnnualUpdateDecision> annualUpdateDecision(
    DatabaseExecutor db,
    DateTime now, {
    DateTime? lastCheckedAt,
  }) async {
    DateTime taipei(DateTime value) =>
        value.toUtc().add(const Duration(hours: 8));
    final local = taipei(now);
    if (local.month != DateTime.december) {
      return CalendarAnnualUpdateDecision.outsideDecember;
    }
    final year = local.year;
    final current = await status(db, year);
    if (current == null ||
        !current.isContiguous ||
        !current.hasCanonicalRowDigest ||
        current.sequence < 1 ||
        current.digest.isEmpty) {
      return CalendarAnnualUpdateDecision.currentYearNotVerified;
    }

    final december = await db.query(
      tableName,
      columns: <String>['calendar_date', 'is_business_day'],
      where: 'source_year = ? AND calendar_date >= ? AND calendar_date <= ?',
      whereArgs: <Object?>[year, '$year-12-01', '$year-12-31'],
      orderBy: 'calendar_date ASC',
    );
    if (december.length != 31) {
      return CalendarAnnualUpdateDecision.currentYearNotVerified;
    }
    String? firstBusinessDay;
    for (final row in december) {
      if (row['is_business_day'] == 1) {
        firstBusinessDay = row['calendar_date'] as String;
        break;
      }
    }
    if (firstBusinessDay == null) {
      return CalendarAnnualUpdateDecision.currentYearNotVerified;
    }
    final today = local.toIso8601String().substring(0, 10);
    if (today.compareTo(firstBusinessDay) < 0) {
      return CalendarAnnualUpdateDecision.beforeFirstBusinessDay;
    }

    final next = await status(db, year + 1);
    if (next != null) {
      if (next.isContiguous &&
          next.hasCanonicalRowDigest &&
          next.sequence > 0 &&
          next.digest.isNotEmpty) {
        return CalendarAnnualUpdateDecision.nextYearInstalled;
      }
      // Never let a foreground trigger overwrite damaged/partial next-year
      // rows. Existing install() must also reject an inconsistent year.
      return CalendarAnnualUpdateDecision.nextYearUntrusted;
    }
    // B2.18: future-dated receipts cannot suppress a real official check.
    // Compare absolute instants before comparing the Taipei calendar date.
    if (lastCheckedAt != null &&
        !lastCheckedAt.isAfter(now) &&
        taipei(lastCheckedAt).toIso8601String().substring(0, 10) == today) {
      return CalendarAnnualUpdateDecision.checkedToday;
    }
    return CalendarAnnualUpdateDecision.checkOfficialSource;
  }

  // B2.5: revision reads and replacement writes must share the same
  // transaction. Otherwise concurrent refreshes can both accept a stale
  // pre-transaction revision and silently downgrade the verified year LKG.
  Future<CalendarPackageInstallResult> install(
    Database db,
    TaiwanBusinessCalendarYearPackage package, {
    DateTime? importedAt,
  }) {
    return db.transaction((txn) async {
      final current = await _rows(txn, package.sourceYear);
      final metadata = await _metadata(current);
      if (metadata != null) {
        if (metadata.revisionSequence > package.revisionSequence) {
          throw CalendarPackageConflictException(
            'Year ${package.sourceYear} already has newer revision '
            '${metadata.revisionSequence}.',
          );
        }
        if (metadata.revisionSequence == package.revisionSequence) {
          if (_matches(current, package)) {
            return _result(CalendarPackageInstallDisposition.unchanged, package);
          }
          throw CalendarPackageConflictException(
            'Year ${package.sourceYear} sequence ${package.revisionSequence} '
            'already exists with different content.',
          );
        }
      } else if (current.isNotEmpty && !_isConsistentLegacy(current)) {
        throw CalendarPackageConflictException(
          'Year ${package.sourceYear} contains inconsistent calendar metadata.',
        );
      }

      final timestamp = (importedAt ?? DateTime.now().toUtc())
          .toUtc()
          .toIso8601String();
      await txn.delete(
        tableName,
        where: 'source_year = ?',
        whereArgs: <Object?>[package.sourceYear],
      );
      final batch = txn.batch();
      final revision = package.storedMetadata.encode();
      for (final day in package.days) {
        batch.insert(tableName, <String, Object?>{
          'calendar_date': day.dateKey,
          'is_business_day': day.isBusinessDay ? 1 : 0,
          'day_label': day.label,
          'source_year': package.sourceYear,
          'source_revision': revision,
          'source_url': package.sourceUrl,
          'updated_at': timestamp,
        });
      }
      await batch.commit(noResult: true);
      // B2.19: an AFTER INSERT trigger may silently alter or delete a row
      // without failing the batch. Verify the durable candidate inside this
      // SAME transaction; any mismatch rolls back the previous verified LKG.
      final writtenRows = await _rows(txn, package.sourceYear);
      final writtenMetadata = await _metadata(writtenRows);
      if (writtenMetadata == null ||
          writtenMetadata.digest != package.digest ||
          !_matches(writtenRows, package, expectedImportedAt: timestamp)) {
        throw CalendarPackageConflictException(
          'Year ${package.sourceYear} post-install row proof mismatch.',
        );
      }
      return _result(CalendarPackageInstallDisposition.installed, package);
    });
  }

  Future<CalendarPackageStatus?> status(
    DatabaseExecutor db,
    int year,
  ) async {
    final rows = await _rows(db, year);
    if (rows.isEmpty) return null;
    final metadata = await _metadata(rows);
    // B2.23: historical SQLite rowid tables can contain NULL TEXT PRIMARY
    // KEY values, and TEXT-affinity columns can still hold BLOBs. A damaged
    // year is not a calendar authority; never let status() throw TypeError.
    final firstRow = rows.first;
    final start = firstRow['calendar_date'];
    final end = rows.last['calendar_date'];
    final revision = firstRow['source_revision'];
    final sourceUrl = firstRow['source_url'];
    final importedAt = firstRow['updated_at'];
    if (start is! String ||
        end is! String ||
        revision is! String ||
        sourceUrl is! String ||
        importedAt is! String) {
      return null;
    }
    return CalendarPackageStatus(
      year: year,
      start: start,
      end: end,
      rowCount: rows.length,
      revision: metadata?.sourceRevision ?? revision,
      sequence: metadata?.revisionSequence ?? 0,
      digest: metadata?.digest ?? '',
      sourceUrl: sourceUrl,
      importedAt: importedAt,
      isContiguous: metadata != null || _isConsistentLegacy(rows),
      hasCanonicalRowDigest: metadata?.generatedAt != null,
    );
  }

  Future<List<Map<String, Object?>>> _rows(
    DatabaseExecutor db,
    int year,
  ) {
    return db.query(
      tableName,
      where: 'source_year = ?',
      whereArgs: <Object?>[year],
      orderBy: 'calendar_date ASC',
    );
  }

  Future<TaiwanBusinessCalendarStoredMetadata?> _metadata(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return null;
    final values = rows.map((row) => row['source_revision']).toSet();
    if (values.length != 1 || values.single is! String) return null;
    final metadata = TaiwanBusinessCalendarStoredMetadata.tryDecode(
      values.single! as String,
    );
    // B2.1: a parseable metadata envelope alone is not an installed-year
    // authority. Require full-year row/metadata coherence before allowing a
    // higher revision to replace it. This is structural validation, NOT a
    // recomputation of the source package SHA-256 from SQLite rows.
    if (metadata == null ||
        metadata.formatVersion !=
            TaiwanBusinessCalendarYearPackage.currentFormatVersion ||
        metadata.sourceYear < 1900 ||
        metadata.sourceYear > 9999 ||
        metadata.sourceYear != rows.first['source_year'] ||
        metadata.revisionSequence < 1 ||
        metadata.sourceRevision.trim().isEmpty ||
        DateTime.tryParse(metadata.sourcePublishedAt) == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(metadata.digest)) {
      return null;
    }
    final firstDay = DateTime.utc(metadata.sourceYear, 1, 1);
    final expectedCount = DateTime.utc(metadata.sourceYear + 1, 1, 1)
        .difference(firstDay)
        .inDays;
    if (rows.length != expectedCount ||
        metadata.rowCount != expectedCount ||
        metadata.coverageStart !=
            firstDay.toIso8601String().substring(0, 10) ||
        metadata.coverageEnd !=
            DateTime.utc(metadata.sourceYear, 12, 31)
                .toIso8601String()
                .substring(0, 10)) {
      return null;
    }
    final url = rows.first['source_url'];
    // B2.3: installed metadata must retain the same official-host authority
    // as the incoming package; a replaced SQLite source URL is not LKG.
    if (url is! String ||
        !TaiwanBusinessCalendarPackageCodec.isApprovedOfficialSourceUrl(url)) {
      return null;
    }
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final expectedDate = firstDay
          .add(Duration(days: index))
          .toIso8601String()
          .substring(0, 10);
      if (row['source_year'] != metadata.sourceYear ||
          row['calendar_date'] != expectedDate ||
          row['source_url'] != url ||
          row['source_revision'] != rows.first['source_revision'] ||
          row['day_label'] is! String ||
          row['is_business_day'] is! int ||
          (row['is_business_day'] != 0 && row['is_business_day'] != 1)) {
        return null;
      }
    }
    // B2.16: structurally valid 0/1 flags and labels may still be damaged.
    // New installations retain generated_at, allowing a full canonical
    // SHA-256 rebuild from persisted rows before accepting year authority.
    // Historical envelopes without generated_at retain structural-only
    // compatibility and are not asserted to have cryptographic row proof.
    if (metadata.generatedAt != null) {
      if (DateTime.tryParse(metadata.generatedAt!) == null) return null;
      // B2.22: the canonical day digest excludes local import provenance.
      // A later SQLite rewrite of one timestamp must revoke verified LKG,
      // even if every day/label still hashes to the original package.
      // New-format installs issue one UTC timestamp for the entire year.
      final importedAt = rows.first['updated_at'];
      if (importedAt is! String ||
          !importedAt.endsWith('Z') ||
          DateTime.tryParse(importedAt) == null ||
          rows.any((row) => row['updated_at'] != importedAt)) {
        return null;
      }
      try {
        final rebuilt = await const TaiwanBusinessCalendarPackageCodec().build(
          sourceYear: metadata.sourceYear,
          sourceRevision: metadata.sourceRevision,
          revisionSequence: metadata.revisionSequence,
          sourceUrl: url,
          sourcePublishedAt: metadata.sourcePublishedAt,
          generatedAt: metadata.generatedAt!,
          days: rows.map((row) => TaiwanBusinessCalendarPackageDay(
            dateKey: row['calendar_date'] as String,
            isBusinessDay: row['is_business_day'] == 1,
            label: row['day_label'] as String,
          )).toList(growable: false),
        );
        if (rebuilt.digest != metadata.digest) return null;
      } on TaiwanBusinessCalendarPackageException {
        return null;
      }
    }
    return metadata;
  }

  // B2: only a *complete* legacy calendar may be upgraded. A damaged
  // package-metadata string is not legacy, even if its dates are contiguous.
  // Never replace an incomplete or ambiguous installed year with new data.
  bool _isConsistentLegacy(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return false;
    final revisions = rows.map((row) => row['source_revision']).toSet();
    final urls = rows.map((row) => row['source_url']).toSet();
    if (revisions.length != 1 || urls.length != 1) return false;
    final revision = revisions.single;
    final legacyUrl = urls.single;
    // A complete historical row set with an unapproved source is not an
    // authoritative legacy year and must not be silently upgraded.
    if (legacyUrl is! String ||
        !TaiwanBusinessCalendarPackageCodec.isApprovedOfficialSourceUrl(
          legacyUrl,
        )) {
      return false;
    }
    if (revision is! String || revision.trim().isEmpty ||
        revision.trimLeft().startsWith('{') ||
        revision.trimLeft().startsWith('[')) {
      return false;
    }
    final sourceYear = rows.first['source_year'];
    if (sourceYear is! int || sourceYear < 1900 || sourceYear > 9999) {
      return false;
    }
    final firstDay = DateTime.utc(sourceYear, 1, 1);
    final expectedCount =
        DateTime.utc(sourceYear + 1, 1, 1).difference(firstDay).inDays;
    if (rows.length != expectedCount) return false;
    for (var index = 0; index < rows.length; index++) {
      final expectedDate = firstDay
          .add(Duration(days: index))
          .toIso8601String()
          .substring(0, 10);
      // Legacy SQLite schemas may lack modern NOT NULL/CHECK constraints.
      // Reject damaged day data before any transactional year replacement.
      final row = rows[index];
      final flag = row['is_business_day'];
      if (row['source_year'] != sourceYear ||
          row['calendar_date'] != expectedDate ||
          flag is! int || (flag != 0 && flag != 1) ||
          row['day_label'] is! String) {
        return false;
      }
    }
    return true;
  }

  bool _matches(
    List<Map<String, Object?>> rows,
    TaiwanBusinessCalendarYearPackage package, {
    String? expectedImportedAt,
  }) {
    if (rows.length != package.days.length) return false;
    final revision = package.storedMetadata.encode();
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final day = package.days[index];
      // B2.21: legacy SQLite can return TEXT flags. Reject non-integer or
      // out-of-domain values before comparison, never throw an untyped cast.
      // B2.20: post-write provenance must equal the timestamp issued for
      // this transaction; a silent AFTER INSERT mutation is not LKG.
      if ((expectedImportedAt != null &&
              row['updated_at'] != expectedImportedAt) ||
          row['calendar_date'] != day.dateKey ||
          (row['is_business_day'] is! int ||
              (row['is_business_day'] != 0 && row['is_business_day'] != 1) ||
              row['is_business_day'] != (day.isBusinessDay ? 1 : 0)) ||
          row['day_label'] != day.label ||
          row['source_revision'] != revision ||
          row['source_url'] != package.sourceUrl) {
        return false;
      }
    }
    return true;
  }

  CalendarPackageInstallResult _result(
    CalendarPackageInstallDisposition disposition,
    TaiwanBusinessCalendarYearPackage package,
  ) {
    return CalendarPackageInstallResult(
      disposition: disposition,
      year: package.sourceYear,
      revision: package.sourceRevision,
      sequence: package.revisionSequence,
      digest: package.digest,
      rowCount: package.days.length,
    );
  }
}
