import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_status_page.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_annual_source_check.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_csv_import.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_official_116_stage.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package_service.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_pinned_116_install.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// B2.7: explicit isolated source lab only; never included in routine test/.
void main() {
  const codec = TaiwanBusinessCalendarOfficialCsvCodec();
  const service = TaiwanBusinessCalendarPackageService();
  const url = 'https://www.dgpa.gov.tw/FileConversion?filename=dgpa%2Ffiles%2F202607%2Ff538b1ff-ba60-4c63-9477-10db8e6612d1.csv&name=116%E5%B9%B4%E4%B8%AD%E8%8F%AF%E6%B0%91%E5%9C%8B%E6%94%BF%E5%BA%9C%E8%A1%8C%E6%94%BF%E6%A9%9F%E9%97%9C%E8%BE%A6%E5%85%AC%E6%97%A5%E6%9B%86%E8%A1%A8_utf8bom.csv&nfix=';

  setUpAll(() {
    sqfliteFfiInit();
    // B2.13 CI #1324: Flutter WidgetTester uses FakeAsync; the worker-isolate
    // FFI factory deadlocks widget pumps. Keep REAL isolated SQLite and
    // transactional assertions, but run its FFI work in the test isolate.
    databaseFactory = databaseFactoryFfiNoIsolate;
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

  test('B2.12 genuine pinned source installs once with explicit consent', () async {
    final bytes = await officialBytes();
    const installer = TaiwanBusinessCalendarPinned116Installer();
    final first = await installer.prepare(bytes);
    final again = await installer.prepare(bytes);
    expect(first.digest, again.digest,
        reason: 'Pinned baseline package must be byte-stable across retries.');
    expect(first.sourceRevision, contains(
        TaiwanBusinessCalendarOfficial116Stage.pinnedSha256));
    expect(first.revisionSequence, 1);
    expect(first.sourcePublishedAt, '2026-05-21');

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
    await expectLater(installer.install(db, bytes, userConfirmed: false),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await service.status(db, 2027), isNull);

    final installed = await installer.install(db, bytes, userConfirmed: true);
    expect(installed.disposition, CalendarPackageInstallDisposition.installed);
    expect(installed.rowCount, 365);
    final retry = await installer.install(db, bytes, userConfirmed: true);
    expect(retry.disposition, CalendarPackageInstallDisposition.unchanged);
    expect(retry.digest, installed.digest);
    final status = await service.status(db, 2027);
    expect(status!.rowCount, 365);
    expect(status.sequence, 1);
    expect(status.digest, first.digest);
    expect(status.sourceUrl, TaiwanBusinessCalendarPinned116Installer.sourceUrl);

    final changed = Uint8List.fromList(bytes);
    changed[changed.length - 1] ^= 1;
    await expectLater(installer.install(db, changed, userConfirmed: true),
        throwsA(isA<TaiwanBusinessCalendarPackageException>()));
    final preserved = await service.status(db, 2027);
    expect(preserved!.digest, first.digest);
    expect(preserved.sequence, 1);
  });

  test('B2.12 real source initial install rolls back on mid-batch abort',
      () async {
    final bytes = await officialBytes();
    const installer = TaiwanBusinessCalendarPinned116Installer();
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
    await db.execute('''
      CREATE TRIGGER b2_initial_abort
      BEFORE INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2027-07-01'
      BEGIN SELECT RAISE(ABORT, 'isolated-initial-install-rollback'); END
    ''');
    await expectLater(installer.install(db, bytes, userConfirmed: true),
        throwsA(isA<DatabaseException>()));
    expect(await service.status(db, 2027), isNull);
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM taiwan_business_calendar_days');
    expect(rows.single['count'], 0);
  });


  // B2.13 Lab #70 first failure: testWidgets runs in FakeAsync. Reading the
  // real CSV from disk (and awaiting its SHA) before the first widget pump
  // stalls the test for ten minutes. Load and SHA-verify original DGPA bytes
  // in setUpAll's real async zone; never replace them with a synthetic CSV.
  late Uint8List verifiedOfficialUiBytes;
  setUpAll(() async {
    verifiedOfficialUiBytes = Uint8List.fromList(await officialBytes());
  });

  testWidgets('B2.13 genuine DGPA UI cancel=zero writes, confirm=365 days',
      (tester) async {
    // Only immutable, preverified bytes enter WidgetTester's FakeAsync zone.
    final bytes = verifiedOfficialUiBytes;
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
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        csvBytesPicker: () async => Uint8List.fromList(bytes),
        clock: () => DateTime.utc(2026, 11, 3),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.previewKey));
    await tester.pumpAndSettle();
    final install = find.byKey(TaiwanBusinessCalendarStatusPage.installKey);
    expect(install, findsOneWidget);
    await tester.ensureVisible(install);
    await tester.tap(install);
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.confirmInstallKey),
        findsOneWidget);
    await tester.tap(find.byKey(
        TaiwanBusinessCalendarStatusPage.cancelInstallKey));
    await tester.pumpAndSettle();
    expect(await service.status(db, 2027), isNull);

    await tester.ensureVisible(install);
    await tester.tap(install);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        TaiwanBusinessCalendarStatusPage.confirmInstallKey));
    await tester.pumpAndSettle();
    final installed = await service.status(db, 2027);
    expect(installed, isNotNull);
    expect(installed!.rowCount, 365);
    expect(installed.isContiguous, isTrue);
    expect(installed.sequence, 1);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.installKey), findsNothing);
    expect(find.textContaining('2027 年：365 日已驗證'), findsOneWidget);
    expect(await service.status(db, 2026), isNull,
        reason: '2027 install must not invent current-year authority.');
  });


  test('B2.14b genuine DGPA 116 bytes produce read-only source receipt',
      () async {
    final original = await officialBytes();
    var fetches = 0;
    final checker = TaiwanBusinessCalendarAnnualSourceCheck(
      readPinnedCsv: () async {
        fetches++;
        return Uint8List.fromList(original);
      },
    );
    expect(fetches, 0);
    final receipt = await checker.check();
    expect(fetches, 1);
    expect(receipt.sha256,
        TaiwanBusinessCalendarOfficial116Stage.pinnedSha256);
    expect(receipt.days, 365);
    expect(receipt.holidays, 121);
    final tampered = Uint8List.fromList(original);
    tampered[tampered.length - 1] ^= 1;
    await expectLater(
      TaiwanBusinessCalendarAnnualSourceCheck(
        readPinnedCsv: () async => tampered,
      ).check(),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
  });

}
