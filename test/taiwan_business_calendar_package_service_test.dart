import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const codec = TaiwanBusinessCalendarPackageCodec();
  const service = TaiwanBusinessCalendarPackageService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('installs one year transactionally and reports coverage', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final package = await _package(codec, year: 2028, sequence: 1);

    final result = await service.install(
      db,
      package,
      importedAt: DateTime.utc(2027, 7, 1),
    );
    final status = await service.status(db, 2028);

    expect(result.disposition, CalendarPackageInstallDisposition.installed);
    expect(await db.query('taiwan_business_calendar_days'), hasLength(366));
    expect(status, isNotNull);
    expect(status!.start, '2028-01-01');
    expect(status.end, '2028-12-31');
    expect(status.rowCount, 366);
    expect(status.revision, 'DGPA-2028-test-r1');
    expect(status.sequence, 1);
    expect(status.digest, package.digest);
    expect(status.isContiguous, isTrue);
  });

  test('identical revision is idempotent', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final package = await _package(codec, year: 2028, sequence: 1);

    await service.install(db, package);
    final second = await service.install(db, package);

    expect(second.disposition, CalendarPackageInstallDisposition.unchanged);
    expect(await db.query('taiwan_business_calendar_days'), hasLength(366));
  });

  test('newer revision replaces only its year and preserves other years', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyDay(db, year: 2027, date: '2027-12-31');
    final first = await _package(codec, year: 2028, sequence: 1);
    final second = await _package(
      codec,
      year: 2028,
      sequence: 2,
      closedDate: '2028-07-03',
    );

    await service.install(db, first);
    await service.install(db, second);

    expect(
      await db.query(
        'taiwan_business_calendar_days',
        where: 'source_year = 2027',
      ),
      hasLength(1),
    );
    final changed = await db.query(
      'taiwan_business_calendar_days',
      where: 'calendar_date = ?',
      whereArgs: <Object?>['2028-07-03'],
    );
    expect((changed.single['is_business_day'] as num).toInt(), 0);
    expect((await service.status(db, 2028))!.sequence, 2);
  });

  test('older and equal conflicting revisions are rejected', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final current = await _package(codec, year: 2028, sequence: 2);
    final older = await _package(codec, year: 2028, sequence: 1);
    final conflict = await _package(
      codec,
      year: 2028,
      sequence: 2,
      closedDate: '2028-07-03',
    );
    await service.install(db, current);

    await expectLater(
      service.install(db, older),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    await expectLater(
      service.install(db, conflict),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    expect((await service.status(db, 2028))!.digest, current.digest);
  });

  test('legacy bundled rows can be upgraded by a versioned package', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyYear(db, 2028);
    final package = await _package(codec, year: 2028, sequence: 1);

    final result = await service.install(db, package);

    expect(result.disposition, CalendarPackageInstallDisposition.installed);
    expect((await service.status(db, 2028))!.sequence, 1);
  });

  test('B2 damaged package metadata is not silently treated as legacy', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final newer = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    // Simulate a damaged metadata envelope in every row. A single shared
    // invalid JSON-shaped revision previously passed the legacy heuristic.
    const damaged = '{"format_version":1,"broken":true}';
    await db.update(
      'taiwan_business_calendar_days',
      <String, Object?>{'source_revision': damaged},
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );

    await expectLater(
      service.install(db, newer),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final rows = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(rows, hasLength(366));
    expect(rows.every((row) => row['source_revision'] == damaged), isTrue);
    expect(rows.every((row) => row['source_url'] == original.sourceUrl), isTrue);
  });

  test('B2 incomplete legacy year is not upgraded or overwritten', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyDay(db, year: 2028, date: '2028-07-01');
    final replacement = await _package(codec, year: 2028, sequence: 1);

    await expectLater(
      service.install(db, replacement),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final rows = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(rows, hasLength(1));
    expect(rows.single['calendar_date'], '2028-07-01');
    expect(rows.single['source_revision'], 'DGPA-legacy-2028');
  });

  test('B2.1 structurally forged stored metadata cannot replace a year',
      () async {
    for (final corruption in <String, Object?>{
      'source_year': 2027,
      'sha256': 'invalid-digest',
      'revision_sequence': 0,
    }.entries) {
      final db = await _openCalendarDatabase();
      final original = await _package(codec, year: 2028, sequence: 1);
      final newer = await _package(codec, year: 2028, sequence: 2);
      await service.install(db, original);
      final rowsBefore = await db.query('taiwan_business_calendar_days',
          where: 'source_year = ?', whereArgs: <Object?>[2028]);
      final metadata = Map<String, Object?>.from(jsonDecode(
        rowsBefore.first['source_revision']! as String,
      ) as Map);
      metadata[corruption.key] = corruption.value;
      final damaged = jsonEncode(metadata);
      await db.update(
        'taiwan_business_calendar_days',
        <String, Object?>{'source_revision': damaged},
        where: 'source_year = ?',
        whereArgs: <Object?>[2028],
      );

      await expectLater(
        service.install(db, newer),
        throwsA(isA<CalendarPackageConflictException>()),
        reason: 'Corrupt ${corruption.key} must not be promoted to legacy.',
      );
      final retained = await db.query('taiwan_business_calendar_days',
          where: 'source_year = ?', whereArgs: <Object?>[2028]);
      expect(retained, hasLength(366));
      expect(retained.every((row) => row['source_revision'] == damaged),
          isTrue);
      expect(retained.every((row) => row['source_url'] == original.sourceUrl),
          isTrue);
      await db.close();
    }
  });

  test('B2.1 partial legacy status is not a complete annual coverage',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyDay(db, year: 2028, date: '2028-07-01');

    final status = await service.status(db, 2028);

    expect(status, isNotNull);
    expect(status!.rowCount, 1);
    expect(status.isContiguous, isFalse);
    expect(status.sequence, 0);
  });


  test('B2.3 corrupted stored official URL rejects replacement and status',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final newer = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    const attackerUrl = 'https://www.dgpa.gov.tw.attacker.example/calendar.csv';
    await db.update(
      'taiwan_business_calendar_days',
      <String, Object?>{'source_url': attackerUrl},
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );

    final status = await service.status(db, 2028);
    expect(status, isNotNull);
    expect(status!.isContiguous, isFalse);
    await expectLater(
      service.install(db, newer),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final retained = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(retained, hasLength(366));
    expect(retained.every((row) => row['source_url'] == attackerUrl), isTrue);
    expect(retained.every((row) =>
        row['source_revision'] == original.storedMetadata.encode()), isTrue);
  });

  test('B2.3 complete legacy year with unapproved URL cannot be promoted',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyYear(db, 2028);
    const attackerUrl = 'https://attacker.example/calendar.csv';
    await db.update(
      'taiwan_business_calendar_days',
      <String, Object?>{'source_url': attackerUrl},
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    final replacement = await _package(codec, year: 2028, sequence: 1);

    expect((await service.status(db, 2028))!.isContiguous, isFalse);
    await expectLater(
      service.install(db, replacement),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final retained = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(retained, hasLength(366));
    expect(retained.every((row) => row['source_url'] == attackerUrl), isTrue);
    expect(retained.every((row) =>
        row['source_revision'] == 'DGPA-legacy-2028'), isTrue);
  });

  test('failed replacement rolls back the original year', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final first = await _package(codec, year: 2028, sequence: 1);
    final second = await _package(
      codec,
      year: 2028,
      sequence: 2,
      closedDate: '2028-07-03',
    );
    await service.install(db, first);
    await db.execute('''
      CREATE TRIGGER block_calendar_insert
      BEFORE INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2028-07-01'
      BEGIN
        SELECT RAISE(ABORT, 'blocked for rollback test');
      END
    ''');

    await expectLater(
      service.install(db, second),
      throwsA(isA<DatabaseException>()),
    );

    final status = await service.status(db, 2028);
    expect(status!.sequence, 1);
    expect(status.digest, first.digest);
    expect(status.rowCount, 366);
  });

  test('B2.4 official December trigger uses installed workday, not weekends',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    // Synthetic fixture: Friday Dec 1 is an official-style holiday, so the
    // first workday is Monday Dec 4. No real DGPA data is asserted here.
    await service.install(db, await _package(
      codec, year: 2028, sequence: 1, closedDate: '2028-12-01',
    ));
    final before = await db.query('taiwan_business_calendar_days');
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 11, 30, 15, 59)),
      CalendarAnnualUpdateDecision.outsideDecember,
    );
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 3, 15, 59)),
      CalendarAnnualUpdateDecision.beforeFirstBusinessDay,
    );
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 3, 16)),
      CalendarAnnualUpdateDecision.checkOfficialSource,
    );
    expect(
      await service.annualUpdateDecision(
        db, DateTime.utc(2028, 12, 4),
        lastCheckedAt: DateTime.utc(2028, 12, 3, 16, 1),
      ),
      CalendarAnnualUpdateDecision.checkedToday,
    );
    expect(await db.query('taiwan_business_calendar_days'), before,
        reason: 'A foreground eligibility check must not mutate SQLite.');
  });

  test('B2.4 missing, legacy or corrupt years never authorize update',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2028, 12, 4);
    expect(await service.annualUpdateDecision(db, now),
        CalendarAnnualUpdateDecision.currentYearNotVerified);
    await _insertLegacyYear(db, 2028);
    expect(await service.annualUpdateDecision(db, now),
        CalendarAnnualUpdateDecision.currentYearNotVerified);
    await service.install(db, await _package(codec, year: 2028, sequence: 1));
    await _insertLegacyDay(db, year: 2029, date: '2029-01-01');
    expect(await service.annualUpdateDecision(db, now),
        CalendarAnnualUpdateDecision.nextYearUntrusted);
    expect(await db.query('taiwan_business_calendar_days',
        where: 'source_year = ?', whereArgs: <Object?>[2029]), hasLength(1));
  });

  test('B2.4 fully installed next year suppresses duplicate source checks',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await service.install(db, await _package(codec, year: 2028, sequence: 1));
    await service.install(db, await _package(codec, year: 2029, sequence: 1));
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.nextYearInstalled,
    );
    expect((await service.status(db, 2029))!.rowCount, 365);
  });

}

Future<Database> _openCalendarDatabase() async {
  final db = await openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE taiwan_business_calendar_days (
      calendar_date TEXT PRIMARY KEY,
      is_business_day INTEGER NOT NULL,
      day_label TEXT NOT NULL DEFAULT '',
      source_year INTEGER NOT NULL,
      source_revision TEXT NOT NULL,
      source_url TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (is_business_day IN (0, 1))
    )
  ''');
  return db;
}

Future<TaiwanBusinessCalendarYearPackage> _package(
  TaiwanBusinessCalendarPackageCodec codec, {
  required int year,
  required int sequence,
  String? closedDate,
}) {
  return codec.build(
    sourceYear: year,
    sourceRevision: 'DGPA-$year-test-r$sequence',
    revisionSequence: sequence,
    sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
    sourcePublishedAt: '${year - 1}-06-30',
    generatedAt: '${year - 1}-07-01T00:00:00.000Z',
    days: _daysForYear(year, closedDate: closedDate),
  );
}

List<TaiwanBusinessCalendarPackageDay> _daysForYear(
  int year, {
  String? closedDate,
}) {
  final days = <TaiwanBusinessCalendarPackageDay>[];
  var cursor = DateTime.utc(year, 1, 1);
  final end = DateTime.utc(year + 1, 1, 1);
  while (cursor.isBefore(end)) {
    final key = _dateKey(cursor);
    final weekend = cursor.weekday == DateTime.saturday ||
        cursor.weekday == DateTime.sunday;
    final closed = weekend || key == closedDate;
    days.add(
      TaiwanBusinessCalendarPackageDay(
        dateKey: key,
        isBusinessDay: !closed,
        label: closed ? 'closed' : '',
      ),
    );
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

Future<void> _insertLegacyDay(
  Database db, {
  required int year,
  required String date,
}) {
  return db.insert('taiwan_business_calendar_days', <String, Object?>{
    'calendar_date': date,
    'is_business_day': 0,
    'day_label': 'legacy',
    'source_year': year,
    'source_revision': 'DGPA-legacy-$year',
    'source_url': 'https://www.dgpa.gov.tw/informationlist?uid=41',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
}

Future<void> _insertLegacyYear(Database db, int year) async {
  final batch = db.batch();
  for (final day in _daysForYear(year)) {
    batch.insert('taiwan_business_calendar_days', <String, Object?>{
      'calendar_date': day.dateKey,
      'is_business_day': day.isBusinessDay ? 1 : 0,
      'day_label': day.label,
      'source_year': year,
      'source_revision': 'DGPA-legacy-$year',
      'source_url': 'https://www.dgpa.gov.tw/informationlist?uid=41',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
  }
  await batch.commit(noResult: true);
}

String _dateKey(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)}';
}
