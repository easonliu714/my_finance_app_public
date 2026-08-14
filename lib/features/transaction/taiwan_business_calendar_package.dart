import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class TaiwanBusinessCalendarPackageException implements Exception {
  const TaiwanBusinessCalendarPackageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TaiwanBusinessCalendarPackageDay {
  const TaiwanBusinessCalendarPackageDay({
    required this.dateKey,
    required this.isBusinessDay,
    required this.label,
  });

  final String dateKey;
  final bool isBusinessDay;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
        'date': dateKey,
        'is_business_day': isBusinessDay,
        'label': label,
      };

  static TaiwanBusinessCalendarPackageDay fromJson(Object? value) {
    if (value is! Map) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar day must be a JSON object.',
      );
    }
    final map = Map<String, Object?>.from(value);
    final date = map['date'];
    final flag = map['is_business_day'];
    final label = map['label'];
    if (date is! String || date.trim().isEmpty) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar day date must be a non-empty string.',
      );
    }
    if (flag is! bool) {
      throw TaiwanBusinessCalendarPackageException(
        'Calendar day $date has a non-boolean business-day flag.',
      );
    }
    if (label is! String) {
      throw TaiwanBusinessCalendarPackageException(
        'Calendar day $date label must be a string.',
      );
    }
    return TaiwanBusinessCalendarPackageDay(
      dateKey: date.trim(),
      isBusinessDay: flag,
      label: label.trim(),
    );
  }
}

class TaiwanBusinessCalendarStoredMetadata {
  const TaiwanBusinessCalendarStoredMetadata({
    required this.formatVersion,
    required this.sourceYear,
    required this.sourceRevision,
    required this.revisionSequence,
    required this.sourcePublishedAt,
    required this.coverageStart,
    required this.coverageEnd,
    required this.rowCount,
    required this.digest,
  });

  final int formatVersion;
  final int sourceYear;
  final String sourceRevision;
  final int revisionSequence;
  final String sourcePublishedAt;
  final String coverageStart;
  final String coverageEnd;
  final int rowCount;
  final String digest;

  Map<String, Object?> toJson() => <String, Object?>{
        'format_version': formatVersion,
        'source_year': sourceYear,
        'source_revision': sourceRevision,
        'revision_sequence': revisionSequence,
        'source_published_at': sourcePublishedAt,
        'coverage_start': coverageStart,
        'coverage_end': coverageEnd,
        'row_count': rowCount,
        'sha256': digest,
      };

  String encode() => jsonEncode(toJson());

  static TaiwanBusinessCalendarStoredMetadata? tryDecode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final map = Map<String, Object?>.from(decoded);
      final formatVersion = map['format_version'];
      final sourceYear = map['source_year'];
      final sourceRevision = map['source_revision'];
      final revisionSequence = map['revision_sequence'];
      final sourcePublishedAt = map['source_published_at'];
      final coverageStart = map['coverage_start'];
      final coverageEnd = map['coverage_end'];
      final rowCount = map['row_count'];
      final digest = map['sha256'];
      if (formatVersion is! int ||
          sourceYear is! int ||
          sourceRevision is! String ||
          revisionSequence is! int ||
          sourcePublishedAt is! String ||
          coverageStart is! String ||
          coverageEnd is! String ||
          rowCount is! int ||
          digest is! String) {
        return null;
      }
      return TaiwanBusinessCalendarStoredMetadata(
        formatVersion: formatVersion,
        sourceYear: sourceYear,
        sourceRevision: sourceRevision,
        revisionSequence: revisionSequence,
        sourcePublishedAt: sourcePublishedAt,
        coverageStart: coverageStart,
        coverageEnd: coverageEnd,
        rowCount: rowCount,
        digest: digest,
      );
    } on FormatException {
      return null;
    }
  }
}

class TaiwanBusinessCalendarYearPackage {
  const TaiwanBusinessCalendarYearPackage._({
    required this.formatVersion,
    required this.sourceYear,
    required this.sourceRevision,
    required this.revisionSequence,
    required this.sourceUrl,
    required this.sourcePublishedAt,
    required this.generatedAt,
    required this.coverageStart,
    required this.coverageEnd,
    required this.days,
    required this.digest,
  });

  static const int currentFormatVersion = 1;

  final int formatVersion;
  final int sourceYear;
  final String sourceRevision;
  final int revisionSequence;
  final String sourceUrl;
  final String sourcePublishedAt;
  final String generatedAt;
  final String coverageStart;
  final String coverageEnd;
  final List<TaiwanBusinessCalendarPackageDay> days;
  final String digest;

  TaiwanBusinessCalendarStoredMetadata get storedMetadata =>
      TaiwanBusinessCalendarStoredMetadata(
        formatVersion: formatVersion,
        sourceYear: sourceYear,
        sourceRevision: sourceRevision,
        revisionSequence: revisionSequence,
        sourcePublishedAt: sourcePublishedAt,
        coverageStart: coverageStart,
        coverageEnd: coverageEnd,
        rowCount: days.length,
        digest: digest,
      );

  Map<String, Object?> canonicalPayload() => <String, Object?>{
        'format_version': formatVersion,
        'source': <String, Object?>{
          'year': sourceYear,
          'revision': sourceRevision,
          'revision_sequence': revisionSequence,
          'url': sourceUrl,
          'published_at': sourcePublishedAt,
        },
        'generated_at': generatedAt,
        'coverage': <String, Object?>{
          'start': coverageStart,
          'end': coverageEnd,
          'row_count': days.length,
        },
        'days': days.map((day) => day.toJson()).toList(growable: false),
      };

  Map<String, Object?> toJson() => <String, Object?>{
        ...canonicalPayload(),
        'digest': <String, Object?>{
          'algorithm': 'sha256',
          'value': digest,
        },
      };

  String encode() => jsonEncode(toJson());
}

class TaiwanBusinessCalendarPackageCodec {
  const TaiwanBusinessCalendarPackageCodec();

  Future<TaiwanBusinessCalendarYearPackage> build({
    required int sourceYear,
    required String sourceRevision,
    required int revisionSequence,
    required String sourceUrl,
    required String sourcePublishedAt,
    required String generatedAt,
    required List<TaiwanBusinessCalendarPackageDay> days,
  }) async {
    final coverageStart = _dateKey(DateTime.utc(sourceYear, 1, 1));
    final coverageEnd = _dateKey(DateTime.utc(sourceYear, 12, 31));
    final normalizedDays = List<TaiwanBusinessCalendarPackageDay>.unmodifiable(
      days,
    );
    _validateMetadata(
      formatVersion: TaiwanBusinessCalendarYearPackage.currentFormatVersion,
      sourceYear: sourceYear,
      sourceRevision: sourceRevision,
      revisionSequence: revisionSequence,
      sourceUrl: sourceUrl,
      sourcePublishedAt: sourcePublishedAt,
      generatedAt: generatedAt,
      coverageStart: coverageStart,
      coverageEnd: coverageEnd,
    );
    _validateDays(sourceYear, normalizedDays);

    final unsigned = TaiwanBusinessCalendarYearPackage._(
      formatVersion: TaiwanBusinessCalendarYearPackage.currentFormatVersion,
      sourceYear: sourceYear,
      sourceRevision: sourceRevision.trim(),
      revisionSequence: revisionSequence,
      sourceUrl: sourceUrl.trim(),
      sourcePublishedAt: sourcePublishedAt.trim(),
      generatedAt: generatedAt.trim(),
      coverageStart: coverageStart,
      coverageEnd: coverageEnd,
      days: normalizedDays,
      digest: '',
    );
    final digest = await _sha256(jsonEncode(unsigned.canonicalPayload()));
    return TaiwanBusinessCalendarYearPackage._(
      formatVersion: unsigned.formatVersion,
      sourceYear: unsigned.sourceYear,
      sourceRevision: unsigned.sourceRevision,
      revisionSequence: unsigned.revisionSequence,
      sourceUrl: unsigned.sourceUrl,
      sourcePublishedAt: unsigned.sourcePublishedAt,
      generatedAt: unsigned.generatedAt,
      coverageStart: unsigned.coverageStart,
      coverageEnd: unsigned.coverageEnd,
      days: unsigned.days,
      digest: digest,
    );
  }

  Future<TaiwanBusinessCalendarYearPackage> decodeAndValidate(
    String jsonText,
  ) async {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package is not valid JSON.',
      );
    }
    if (decoded is! Map) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package root must be a JSON object.',
      );
    }
    final root = Map<String, Object?>.from(decoded);
    final formatVersion = root['format_version'];
    final source = root['source'];
    final generatedAt = root['generated_at'];
    final coverage = root['coverage'];
    final rawDays = root['days'];
    final digestMap = root['digest'];
    if (formatVersion is! int ||
        source is! Map ||
        generatedAt is! String ||
        coverage is! Map ||
        rawDays is! List ||
        digestMap is! Map) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package has an invalid top-level structure.',
      );
    }

    final sourceMap = Map<String, Object?>.from(source);
    final coverageMap = Map<String, Object?>.from(coverage);
    final digestValues = Map<String, Object?>.from(digestMap);
    final sourceYear = sourceMap['year'];
    final sourceRevision = sourceMap['revision'];
    final revisionSequence = sourceMap['revision_sequence'];
    final sourceUrl = sourceMap['url'];
    final sourcePublishedAt = sourceMap['published_at'];
    final coverageStart = coverageMap['start'];
    final coverageEnd = coverageMap['end'];
    final rowCount = coverageMap['row_count'];
    final algorithm = digestValues['algorithm'];
    final digest = digestValues['value'];
    if (sourceYear is! int ||
        sourceRevision is! String ||
        revisionSequence is! int ||
        sourceUrl is! String ||
        sourcePublishedAt is! String ||
        coverageStart is! String ||
        coverageEnd is! String ||
        rowCount is! int ||
        algorithm != 'sha256' ||
        digest is! String) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package metadata is invalid.',
      );
    }

    final days = rawDays
        .map(TaiwanBusinessCalendarPackageDay.fromJson)
        .toList(growable: false);
    _validateMetadata(
      formatVersion: formatVersion,
      sourceYear: sourceYear,
      sourceRevision: sourceRevision,
      revisionSequence: revisionSequence,
      sourceUrl: sourceUrl,
      sourcePublishedAt: sourcePublishedAt,
      generatedAt: generatedAt,
      coverageStart: coverageStart,
      coverageEnd: coverageEnd,
    );
    _validateDays(sourceYear, days);
    if (rowCount != days.length) {
      throw TaiwanBusinessCalendarPackageException(
        'Calendar package row count $rowCount does not match '
        '${days.length} rows.',
      );
    }

    final package = TaiwanBusinessCalendarYearPackage._(
      formatVersion: formatVersion,
      sourceYear: sourceYear,
      sourceRevision: sourceRevision.trim(),
      revisionSequence: revisionSequence,
      sourceUrl: sourceUrl.trim(),
      sourcePublishedAt: sourcePublishedAt.trim(),
      generatedAt: generatedAt.trim(),
      coverageStart: coverageStart,
      coverageEnd: coverageEnd,
      days: List<TaiwanBusinessCalendarPackageDay>.unmodifiable(days),
      digest: digest.toLowerCase(),
    );
    final calculated = await _sha256(jsonEncode(package.canonicalPayload()));
    if (calculated != package.digest) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package SHA-256 digest does not match its payload.',
      );
    }
    return package;
  }

  void _validateMetadata({
    required int formatVersion,
    required int sourceYear,
    required String sourceRevision,
    required int revisionSequence,
    required String sourceUrl,
    required String sourcePublishedAt,
    required String generatedAt,
    required String coverageStart,
    required String coverageEnd,
  }) {
    if (formatVersion !=
        TaiwanBusinessCalendarYearPackage.currentFormatVersion) {
      throw TaiwanBusinessCalendarPackageException(
        'Unsupported calendar package format version $formatVersion.',
      );
    }
    if (sourceYear < 1900 || sourceYear > 9999) {
      throw TaiwanBusinessCalendarPackageException(
        'Calendar package year $sourceYear is outside the supported range.',
      );
    }
    if (sourceRevision.trim().isEmpty) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package source revision is required.',
      );
    }
    if (revisionSequence < 1) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package revision sequence must be at least 1.',
      );
    }
    final uri = Uri.tryParse(sourceUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package source URL must be an absolute HTTPS URL.',
      );
    }
    if (DateTime.tryParse(sourcePublishedAt.trim()) == null) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package publication date is invalid.',
      );
    }
    if (DateTime.tryParse(generatedAt.trim()) == null) {
      throw const TaiwanBusinessCalendarPackageException(
        'Calendar package generation time is invalid.',
      );
    }
    final expectedStart = _dateKey(DateTime.utc(sourceYear, 1, 1));
    final expectedEnd = _dateKey(DateTime.utc(sourceYear, 12, 31));
    if (coverageStart != expectedStart || coverageEnd != expectedEnd) {
      throw TaiwanBusinessCalendarPackageException(
        'Calendar package coverage must be $expectedStart..$expectedEnd.',
      );
    }
  }

  void _validateDays(
    int sourceYear,
    List<TaiwanBusinessCalendarPackageDay> days,
  ) {
    final start = DateTime.utc(sourceYear, 1, 1);
    final endExclusive = DateTime.utc(sourceYear + 1, 1, 1);
    final expectedCount = endExclusive.difference(start).inDays;
    if (days.length != expectedCount) {
      throw TaiwanBusinessCalendarPackageException(
        'Calendar package for $sourceYear must contain $expectedCount rows; '
        'received ${days.length}.',
      );
    }

    for (var index = 0; index < days.length; index++) {
      final expected = _dateKey(start.add(Duration(days: index)));
      final actual = days[index].dateKey;
      if (actual != expected) {
        throw TaiwanBusinessCalendarPackageException(
          'Calendar package row $index must be $expected; received $actual.',
        );
      }
      final parsed = DateTime.tryParse(actual);
      if (parsed == null || parsed.year != sourceYear) {
        throw TaiwanBusinessCalendarPackageException(
          'Calendar package contains an invalid or wrong-year date: $actual.',
        );
      }
    }
  }

  Future<String> _sha256(String value) async {
    final hash = await Sha256().hash(utf8.encode(value));
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _dateKey(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)}';
  }
}
