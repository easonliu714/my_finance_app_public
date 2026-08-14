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
