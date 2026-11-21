import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_official_116_stage.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package_service.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_pinned_116_install.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const installer = TaiwanBusinessCalendarPinned116Installer();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('B2.12 missing explicit consent never touches SQLite', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await expectLater(
      installer.install(db, Uint8List(0), userConfirmed: false),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name='taiwan_business_calendar_days'",
    );
    expect(tables, isEmpty);
  });

  test('B2.12 unpinned CSV cannot install even with consent', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await expectLater(
      installer.install(db, Uint8List.fromList(<int>[1, 2, 3]),
          userConfirmed: true),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name='taiwan_business_calendar_days'",
    );
    expect(tables, isEmpty);
  });

  test('B2.12 baseline metadata is explicitly local, not DGPA revision', () {
    expect(TaiwanBusinessCalendarPinned116Installer.localBaselineSequence, 1);
    expect(TaiwanBusinessCalendarPinned116Installer.sourceRevision,
        contains(TaiwanBusinessCalendarOfficial116Stage.pinnedSha256));
    expect(TaiwanBusinessCalendarPinned116Installer.calendarAnnouncementDate,
        '2026-05-21');
  });
}
