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
}

class TaiwanBusinessCalendarPackageService {
  const TaiwanBusinessCalendarPackageService();

  static const tableName = 'taiwan_business_calendar_days';

  Future<CalendarPackageInstallResult> install(
    Database db,
    TaiwanBusinessCalendarYearPackage package, {
    DateTime? importedAt,
  }) async {
    final current = await _rows(db, package.sourceYear);
    final metadata = _metadata(current);
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
    await db.transaction((txn) async {
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
    });
    return _result(CalendarPackageInstallDisposition.installed, package);
  }

  Future<CalendarPackageStatus?> status(
    DatabaseExecutor db,
    int year,
  ) async {
    final rows = await _rows(db, year);
    if (rows.isEmpty) return null;
    final metadata = _metadata(rows);
    final start = rows.first['calendar_date'] as String;
    final end = rows.last['calendar_date'] as String;
    return CalendarPackageStatus(
      year: year,
      start: start,
      end: end,
      rowCount: rows.length,
      revision: metadata?.sourceRevision ??
          rows.first['source_revision'] as String,
      sequence: metadata?.revisionSequence ?? 0,
      digest: metadata?.digest ?? '',
      sourceUrl: rows.first['source_url'] as String,
      importedAt: rows.first['updated_at'] as String,
      isContiguous: metadata != null || _isConsistentLegacy(rows),
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

  TaiwanBusinessCalendarStoredMetadata? _metadata(
    List<Map<String, Object?>> rows,
  ) {
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
          row['is_business_day'] is! int ||
          (row['is_business_day'] != 0 && row['is_business_day'] != 1)) {
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
      if (rows[index]['source_year'] != sourceYear ||
          rows[index]['calendar_date'] != expectedDate) {
        return false;
      }
    }
    return true;
  }

  bool _matches(
    List<Map<String, Object?>> rows,
    TaiwanBusinessCalendarYearPackage package,
  ) {
    if (rows.length != package.days.length) return false;
    final revision = package.storedMetadata.encode();
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final day = package.days[index];
      if (row['calendar_date'] != day.dateKey ||
          (row['is_business_day'] as num).toInt() !=
              (day.isBusinessDay ? 1 : 0) ||
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
