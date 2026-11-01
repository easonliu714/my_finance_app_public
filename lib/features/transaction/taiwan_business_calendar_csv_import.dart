import 'dart:convert';
import 'dart:typed_data';

import 'taiwan_business_calendar_package.dart';

/// B2.6 manual CSV adapter only. A claimed source URL does not authenticate
/// user-selected bytes; callers must require provenance review before install.
class TaiwanBusinessCalendarOfficialCsvCodec {
  const TaiwanBusinessCalendarOfficialCsvCodec();
  static const maxCsvBytes = 256 * 1024;
  static const _header = ['西元日期', '星期', '是否放假', '備註'];
  static const _weekdays = ['日', '一', '二', '三', '四', '五', '六'];

  Future<TaiwanBusinessCalendarYearPackage> decodeManualCsv(
    Uint8List bytes, {
    required int sourceYear,
    required String sourceRevision,
    required int revisionSequence,
    required String sourceUrl,
    required String sourcePublishedAt,
    required String generatedAt,
  }) async {
    if (bytes.isEmpty || bytes.lengthInBytes > maxCsvBytes) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar CSV is empty or exceeds the 256KiB limit.');
    }
    if (!TaiwanBusinessCalendarPackageCodec.isApprovedOfficialSourceUrl(sourceUrl)) {
      throw const TaiwanBusinessCalendarPackageException(
        'Manual CSV must identify an approved official source.');
    }
    String csv;
    try {
      csv = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const TaiwanBusinessCalendarPackageException('Invalid UTF-8 CSV.');
    }
    if (csv.startsWith('\uFEFF')) csv = csv.substring(1);
    final rows = _records(csv);
    if (rows.isEmpty || rows.first.length != 4 ||
        !_header.every((v) => rows.first[_header.indexOf(v)].trim() == v)) {
      throw const TaiwanBusinessCalendarPackageException(
        'Expected DGPA date, weekday, holiday and note CSV columns.');
    }
    if (sourceYear < 1900 || sourceYear > 9998) {
      throw const TaiwanBusinessCalendarPackageException('Invalid CSV year.');
    }
    final first = DateTime.utc(sourceYear, 1, 1);
    final count = DateTime.utc(sourceYear + 1, 1, 1).difference(first).inDays;
    if (rows.length != count + 1) {
      throw const TaiwanBusinessCalendarPackageException(
        'CSV must contain exactly one full 365/366-day year.');
    }
    final days = <TaiwanBusinessCalendarPackageDay>[];
    for (var i = 0; i < count; i++) {
      final row = rows[i + 1];
      final day = first.add(Duration(days: i));
      final key = day.toIso8601String().substring(0, 10);
      if (row.length != 4 || row[0].trim() != key.replaceAll('-', '') ||
          row[1].trim() != _weekdays[day.weekday % 7]) {
        throw TaiwanBusinessCalendarPackageException(
          'Missing, duplicated, wrong-year or wrong-weekday CSV row ${i + 2}');
      }
      final flag = row[2].trim();
      if (flag != '0' && flag != '2') {
        throw TaiwanBusinessCalendarPackageException(
          'DGPA holiday flag must be 0 or 2 at row ${i + 2}');
      }
      if (row[3].length > 200) {
        throw const TaiwanBusinessCalendarPackageException('CSV note too long.');
      }
      days.add(TaiwanBusinessCalendarPackageDay(
        dateKey: key, isBusinessDay: flag == '0', label: row[3].trim()));
    }
    // Reuse the existing complete-year validator and SHA-256 package builder.
    return const TaiwanBusinessCalendarPackageCodec().build(
      sourceYear: sourceYear, sourceRevision: sourceRevision,
      revisionSequence: revisionSequence, sourceUrl: sourceUrl,
      sourcePublishedAt: sourcePublishedAt, generatedAt: generatedAt,
      days: days);
  }

  // Strict quoted CSV, including CRLF and quoted embedded newline. Fail
  // closed on malformed quotes or surplus columns; no silently dropped rows.
  List<List<String>> _records(String input) {
    final result = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var start = true;
    var closed = false;
    void fieldEnd() {
      row.add(field.toString());
      field = StringBuffer();
      start = true;
      closed = false;
      if (row.length > 4) {
        throw const TaiwanBusinessCalendarPackageException('Extra CSV column.');
      }
    }
    void rowEnd() {
      fieldEnd();
      result.add(List<String>.unmodifiable(row));
      row = <String>[];
      if (result.length > 367) {
        throw const TaiwanBusinessCalendarPackageException('Extra CSV rows.');
      }
    }
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          field.write(c);
        }
      } else if (c == ',') {
        fieldEnd();
      } else if (c == '\r' || c == '\n') {
        if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        rowEnd();
      } else if (c == '"' && start) {
        quoted = true;
        start = false;
      } else if (c == '"' || closed) {
        throw const TaiwanBusinessCalendarPackageException('Malformed CSV quote.');
      } else {
        field.write(c);
        start = false;
      }
    }
    if (quoted) {
      throw const TaiwanBusinessCalendarPackageException('Unclosed CSV quote.');
    }
    if (row.isNotEmpty || field.isNotEmpty || !start) rowEnd();
    return result;
  }
}
