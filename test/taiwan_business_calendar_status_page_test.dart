import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_status_page.dart';
import 'package:my_finance_app/routing/app_router.dart';
import 'package:sqflite/sqflite.dart';

void main() {
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
    // Avoid FFI I/O under Flutter fake async; all writes are forbidden.
    final db = _ReadOnlyCalendarDb();
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
    expect(db.readCount, greaterThanOrEqualTo(2));
    expect(db.writeAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B2 oversize CSV rejects before hashing, never writes',
      (tester) async {
    // Avoid FFI I/O under Flutter fake async; all writes are forbidden.
    final db = _ReadOnlyCalendarDb();
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
    expect(db.readCount, greaterThanOrEqualTo(2));
    expect(db.writeAttempts, 0);
    expect(tester.takeException(), isNull);
  });
  // B2 Taiwan midnight/year rollover: the display and SQLite query must
  // agree with the existing annualUpdateDecision Taipei (+08:00) clock.
  testWidgets('B2 UTC Dec 31 evening reads Taiwan next-year status only',
      (tester) async {
    final db = _ReadOnlyCalendarDb();
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        clock: () => DateTime.utc(2026, 12, 31, 16, 30),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('2027 年：尚未安裝'), findsOneWidget);
    expect(find.textContaining('2028 年：尚未安裝'), findsOneWidget);
    expect(find.textContaining('尚未進入 12 月'), findsOneWidget);
    expect(db.queriedYears, <int>[2027, 2028]);
    expect(db.writeAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B2 UTC Nov 30 evening enters Taiwan December, not November',
      (tester) async {
    final db = _ReadOnlyCalendarDb();
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        clock: () => DateTime.utc(2026, 11, 30, 16, 30),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026 年：尚未安裝'), findsOneWidget);
    expect(find.textContaining('2027 年：尚未安裝'), findsOneWidget);
    expect(find.textContaining('本年度資料尚未驗證'), findsOneWidget);
    expect(db.queriedYears, <int>[2026, 2027, 2026]);
    expect(db.writeAttempts, 0);
    expect(tester.takeException(), isNull);
  });

}

// No real SQLite or Owner data: query-only test double, explicit write audit.
// Existing isolated transactional SQLite tests remain authoritative and intact.
class _ReadOnlyCalendarDb implements DatabaseExecutor {
  int readCount = 0;
  int writeAttempts = 0;
  final queriedYears = <int>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #query) {
      readCount++;
      final args = invocation.namedArguments[#whereArgs] as List<Object?>?;
      if (args != null && args.isNotEmpty && args.first is int) {
        queriedYears.add(args.first! as int);
      }
      return Future<List<Map<String, Object?>>>.value(
        <Map<String, Object?>>[],
      );
    }
    writeAttempts++;
    throw StateError('B2 status/preview widget must not write');
  }
}
