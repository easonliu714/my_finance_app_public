import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package_service.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_status_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // B2.13 CI #1324: Flutter WidgetTester uses FakeAsync; the worker-isolate
    // FFI factory deadlocks widget pumps. Keep REAL isolated SQLite and
    // transactional assertions, but run its FFI work in the test isolate.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Future<Database> calendarDb() async {
    final db = await openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE taiwan_business_calendar_days (
        calendar_date TEXT PRIMARY KEY, is_business_day INTEGER NOT NULL,
        day_label TEXT NOT NULL DEFAULT '', source_year INTEGER NOT NULL,
        source_revision TEXT NOT NULL, source_url TEXT NOT NULL,
        updated_at TEXT NOT NULL, CHECK (is_business_day IN (0, 1))
      )
    ''');
    return db;
  }

  testWidgets('B2.13 canceled picker cannot expose installation or write',
      (tester) async {
    final db = await calendarDb();
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        csvBytesPicker: () async => null,
        clock: () => DateTime.utc(2026, 11, 3),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.previewKey));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.installKey), findsNothing);
    expect(await const TaiwanBusinessCalendarPackageService().status(db, 2027),
        isNull);
  });

  testWidgets('B2.13 wrong SHA fails closed before consent and SQLite',
      (tester) async {
    final db = await calendarDb();
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        csvBytesPicker: () async => Uint8List.fromList(<int>[1, 2, 3]),
        clock: () => DateTime.utc(2026, 11, 3),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.previewKey));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.installKey), findsNothing);
    expect(find.textContaining('SHA-256 不符'), findsOneWidget);
    expect(await const TaiwanBusinessCalendarPackageService().status(db, 2027),
        isNull);
  });
}
