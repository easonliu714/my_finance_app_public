import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_status_page.dart';
import 'package:my_finance_app/routing/app_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('B2 public 116 CSV pin matches real source lab, never a synthetic pin', () {
    final source = File('tool/b2_official_calendar_source_lab.py')
        .readAsStringSync();
    expect(source, contains('https://www.dgpa.gov.tw/FileConversion?'));
    final workflow = File('.github/workflows/b2_official_calendar_source_lab.yml');
    expect(workflow.existsSync(), isTrue);
    final page = File(
      'lib/features/transaction/taiwan_business_calendar_status_page.dart',
    ).readAsStringSync();
    expect(page, contains(
      'e30df188649bf5347db3ec43fa989af2cc8d93d793fbe5c9891601e6cce4acf3',
    ));
  });

  test('B2 status page has an owner-visible governed route', () {
    final routes = buildAppRoutes().whereType<GoRoute>();
    expect(routes.any((route) =>
        route.name == TaiwanBusinessCalendarStatusPage.routeName &&
        route.path == TaiwanBusinessCalendarStatusPage.routePath), isTrue);
  });

  testWidgets('B2 unverified year and mismatched CSV fail closed without writes',
      (tester) async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE taiwan_business_calendar_days (
        calendar_date TEXT PRIMARY KEY,
        is_business_day INTEGER NOT NULL,
        day_label TEXT NOT NULL DEFAULT '',
        source_year INTEGER NOT NULL,
        source_revision TEXT NOT NULL,
        source_url TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        clock: () => DateTime.utc(2026, 12, 4),
        csvBytesPicker: () async => Uint8List.fromList(<int>[1, 2, 3]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026 年：尚未安裝'), findsOneWidget);
    expect(find.textContaining('2027 年：尚未安裝'), findsOneWidget);
    expect(find.textContaining('不可自動更新'), findsOneWidget);
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.previewKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('SHA-256 不符'), findsOneWidget);
    expect(await db.query('taiwan_business_calendar_days'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B2 oversize CSV rejects before hashing, never writes',
      (tester) async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE taiwan_business_calendar_days (
        calendar_date TEXT PRIMARY KEY,
        is_business_day INTEGER NOT NULL,
        day_label TEXT NOT NULL DEFAULT '',
        source_year INTEGER NOT NULL,
        source_revision TEXT NOT NULL,
        source_url TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        clock: () => DateTime.utc(2026, 11, 2),
        csvBytesPicker: () async => Uint8List(
          256 * 1024 + 1,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.previewKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('CSV 讀取或驗證失敗'), findsOneWidget);
    expect(await db.query('taiwan_business_calendar_days'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
