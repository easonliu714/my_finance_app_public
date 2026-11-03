import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_csv_import.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_official_116_stage.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// B2.7: explicit isolated source lab only; never included in routine test/.
void main() {
  const codec = TaiwanBusinessCalendarOfficialCsvCodec();
  const service = TaiwanBusinessCalendarPackageService();
  const url = 'https://www.dgpa.gov.tw/FileConversion?filename=dgpa%2Ffiles%2F202607%2Ff538b1ff-ba60-4c63-9477-10db8e6612d1.csv&name=116%E5%B9%B4%E4%B8%AD%E8%8F%AF%E6%B0%91%E5%9C%8B%E6%94%BF%E5%BA%9C%E8%A1%8C%E6%94%BF%E6%A9%9F%E9%97%9C%E8%BE%A6%E5%85%AC%E6%97%A5%E6%9B%86%E8%A1%A8_utf8bom.csv&nfix=';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Uint8List> officialBytes() async {
    final path = Platform.environment['B2_OFFICIAL_CSV_PATH'];
    final expected = Platform.environment['B2_OFFICIAL_CSV_SHA256'];
    expect(path, isNotNull, reason: 'Source acquisition must run first.');
    expect(expected, matches(RegExp(r'^[0-9a-f]{64}$')));
    final bytes = await File(path!).readAsBytes();
    final hash = await Sha256().hash(bytes);
    final actual = hash.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(actual, expected, reason: 'Official raw-byte SHA must match.');
    expect(bytes.length, lessThanOrEqualTo(
        TaiwanBusinessCalendarOfficialCsvCodec.maxCsvBytes));
    return bytes;
  }

  Future<TaiwanBusinessCalendarYearPackage> parse(
    Uint8List bytes, int sequence,
  ) => codec.decodeManualCsv(
    bytes,
    sourceYear: 2027,
    sourceRevision: 'B2.7-lab-only-source-audit',
    revisionSequence: sequence,
    sourceUrl: url,
    sourcePublishedAt: '2026-07-15',
    generatedAt: '2026-11-01T03:15:00Z',
  );

  test('B2.7 official 116 raw SHA and 365-day real parser E2E', () async {
    final bytes = await officialBytes();
    final year = await parse(bytes, 1);
    expect(year.days, hasLength(365));
    expect(year.days.first.dateKey, '2027-01-01');
    expect(year.days.last.dateKey, '2027-12-31');
    expect(year.digest, matches(RegExp(r'^[0-9a-f]{64}$')));
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
    await service.install(db, year);
    final status = await service.status(db, 2027);
    expect(status, isNotNull);
    expect(status!.rowCount, 365);
    expect(status.isContiguous, isTrue);
    expect(status.digest, year.digest);
    expect(status.sequence, 1);

    // Force an actual mid-batch failure: all prior official LKG rows survive.
    await db.execute('''
      CREATE TRIGGER b2_source_abort
      BEFORE INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2027-07-01'
      BEGIN SELECT RAISE(ABORT, 'isolated-rollback'); END
    ''');
    final replacement = await parse(bytes, 2);
    await expectLater(
      service.install(db, replacement),
      throwsA(isA<DatabaseException>()),
    );
    final after = await service.status(db, 2027);
    expect(after!.rowCount, 365);
    expect(after.sequence, 1);
    expect(after.digest, year.digest);

  });

  test('B2.9 actual pinned DGPA 116 bytes pass production parse-only staging',
      () async {
    final bytes = await officialBytes();
    final staged =
        await const TaiwanBusinessCalendarOfficial116Stage().verify(bytes);
    expect(staged.sourceYear, 2027);
    expect(staged.rawSha256,
        TaiwanBusinessCalendarOfficial116Stage.pinnedSha256);
    expect(staged.days, hasLength(365));
    expect(staged.holidayCount, 121);
    expect(staged.days.first.dateKey, '2027-01-01');
    expect(staged.days.last.dateKey, '2027-12-31');
    expect(() => staged.days.clear(), throwsUnsupportedError);
  });

  test('B2.9 one-byte alteration of real source cannot stage', () async {
    final bytes = Uint8List.fromList(await officialBytes());
    bytes[bytes.length - 1] ^= 1;
    await expectLater(
      const TaiwanBusinessCalendarOfficial116Stage().verify(bytes),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
  });

  test('B2.7 official bytes with malformed UTF-8 fail closed', () async {
    final bytes = await officialBytes();
    final corrupted = Uint8List.fromList(<int>[...bytes, 0xff]);
    await expectLater(
      parse(corrupted, 3),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );

  });
}
