import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_csv_import.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const decoder = TaiwanBusinessCalendarOfficialCsvCodec();
  const service = TaiwanBusinessCalendarPackageService();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  Future<TaiwanBusinessCalendarYearPackage> parse(int year, {
    int revision = 1, String? closedDate, Uint8List? data,
    String url = 'https://www.dgpa.gov.tw/FileConversion?filename=calendar.csv',
  }) => decoder.decodeManualCsv(
    data ?? _fixture(year, closedDate: closedDate),
    sourceYear: year, sourceRevision: 'DGPA-reviewed-r' + revision.toString(),
    revisionSequence: revision, sourceUrl: url,
    sourcePublishedAt: '2026-07-15', generatedAt: '2026-11-01T00:00:00Z');

  test('B2.6 full 365/366 rows and quoted 0/2 holiday semantics', () async {
    final a = await parse(2027, closedDate: '2027-01-01');
    final b = await parse(2028, closedDate: '2028-02-29');
    expect(a.days, hasLength(365));
    expect(b.days, hasLength(366));
    expect(a.days.first.isBusinessDay, isFalse);
    expect(a.days.first.label, '元旦,休假');
    expect(b.days.singleWhere((d) => d.dateKey == '2028-02-29')
        .isBusinessDay, isFalse);
    expect(a.digest, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('B2.6 truncated, duplicate, wrong year, weekday, flag and header reject', () async {
    final original = utf8.decode(_fixture(2027));
    final cases = <String>[
      original.split('\r\n').take(365).join('\r\n'),
      original.replaceFirst('20270102', '20270101'),
      original.replaceFirst('20270101', '20280101'),
      original.replaceFirst(',0,', ',1,'),
      original.replaceFirst('20270101,五', '20270101,六'),
      original.replaceFirst('西元日期', '非官方日期'),
    ];
    for (final value in cases) {
      await expectLater(parse(2027,
        data: Uint8List.fromList(utf8.encode(value))),
        throwsA(isA<TaiwanBusinessCalendarPackageException>()));
    }
  });

  test('B2.6 invalid UTF-8, quote, size and forged host reject', () async {
    await expectLater(parse(2027, data: Uint8List.fromList([0xff, 0xfe])),
        throwsA(isA<TaiwanBusinessCalendarPackageException>()));
    final bad = utf8.decode(_fixture(2027, closedDate: '2027-01-01'))
        .replaceFirst('"元旦,休假"', '"unterminated');
    await expectLater(parse(2027,
        data: Uint8List.fromList(utf8.encode(bad))),
        throwsA(isA<TaiwanBusinessCalendarPackageException>()));
    await expectLater(parse(2027, data: Uint8List(
        TaiwanBusinessCalendarOfficialCsvCodec.maxCsvBytes + 1)),
        throwsA(isA<TaiwanBusinessCalendarPackageException>()));
    await expectLater(parse(2027,
        url: 'https://www.dgpa.gov.tw.attacker.example/a.csv'),
        throwsA(isA<TaiwanBusinessCalendarPackageException>()));
  });

  test('B2.6 manual CSV feeds existing transactional LKG rollback', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE taiwan_business_calendar_days (
        calendar_date TEXT PRIMARY KEY, is_business_day INTEGER NOT NULL,
        day_label TEXT NOT NULL DEFAULT '', source_year INTEGER NOT NULL,
        source_revision TEXT NOT NULL, source_url TEXT NOT NULL,
        updated_at TEXT NOT NULL, CHECK (is_business_day IN (0, 1))
      )
    ''');
    final original = await parse(2027);
    final next = await parse(2027, revision: 2, closedDate: '2027-01-01');
    await service.install(db, original);
    await db.execute('''
      CREATE TRIGGER block_csv_update BEFORE INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2027-07-01'
      BEGIN SELECT RAISE(ABORT, 'rollback'); END
    ''');
    await expectLater(service.install(db, next), throwsA(isA<DatabaseException>()));
    final status = await service.status(db, 2027);
    expect(status!.sequence, 1);
    expect(status.digest, original.digest);
    expect(status.rowCount, 365);
    final retained = await db.query('taiwan_business_calendar_days');
    expect(retained, hasLength(365));
    expect(retained.every((r) =>
        r['source_revision'] == original.storedMetadata.encode()), isTrue);
  });
}

Uint8List _fixture(int year, {String? closedDate}) {
  final output = StringBuffer('\uFEFF西元日期,星期,是否放假,備註\r\n');
  const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
  var date = DateTime.utc(year, 1, 1);
  final end = DateTime.utc(year + 1, 1, 1);
  while (date.isBefore(end)) {
    final key = date.toIso8601String().substring(0, 10);
    final closed = key == closedDate;
    output.write(key.replaceAll('-', ''));
    output.write(',');
    output.write(weekdays[date.weekday % 7]);
    output.write(',');
    output.write(closed ? '2' : '0');
    output.write(',');
    output.write(closed ? '"元旦,休假"' : '');
    output.write('\r\n');
    date = date.add(const Duration(days: 1));
  }
  return Uint8List.fromList(utf8.encode(output.toString()));
}
