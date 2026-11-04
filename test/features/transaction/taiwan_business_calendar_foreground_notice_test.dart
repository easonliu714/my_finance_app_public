import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_foreground_notice.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_status_page.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_annual_check_receipt.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_annual_source_check.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_official_116_stage.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  Widget harness(_ReadOnlyDb db, DateTime Function() clock) => MaterialApp(
    home: Scaffold(
      body: TaiwanBusinessCalendarForegroundNotice(
        databaseProvider: () async => db, clock: clock,
      ),
    ),
  );

  testWidgets('B2.14a missing current-year authority never prompts or writes',
      (tester) async {
    final db = _ReadOnlyDb(verified: false);
    await tester.pumpWidget(harness(db, () => DateTime.utc(2026, 11, 30, 16, 1)));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsNothing);
    expect(db.reads, greaterThan(0));
    expect(db.writes, 0);
  });

  testWidgets('B2.14a partial verified year fails closed', (tester) async {
    final db = _ReadOnlyDb(verified: true, partial: true);
    await tester.pumpWidget(harness(db, () => DateTime.utc(2026, 11, 30, 16, 1)));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsNothing);
    expect(db.writes, 0);
  });

  testWidgets('B2.14a Taiwan midnight foreground resume only offers manual check',
      (tester) async {
    // Synthetic full-year rows are test fixtures, NOT official 2026 source.
    final db = _ReadOnlyDb(verified: true);
    var now = DateTime.utc(2026, 11, 30, 15, 59);
    await tester.pumpWidget(harness(db, () => now));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsNothing);
    now = DateTime.utc(2026, 11, 30, 16, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsOneWidget);
    expect(find.textContaining('2027 年官方日曆尚未安裝'), findsOneWidget);
    expect(db.writes, 0);
  });

  testWidgets('B2.14a installed next year suppresses notice', (tester) async {
    final db = _ReadOnlyDb(verified: true, nextInstalled: true);
    await tester.pumpWidget(harness(db, () => DateTime.utc(2026, 11, 30, 16, 1)));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsNothing);
    expect(db.writes, 0);
  });
  testWidgets('B2.14b explicit same-day check is idempotent and read-only',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    var checks = 0;
    // Widget tests must not await the platform SharedPreferences channel.
    // Exercise the same production receipt contract with isolated storage.
    String? raw;
    final receiptStore = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; });
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: receiptStore,
        clock: () => DateTime.utc(2026, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          return const TaiwanBusinessCalendarAnnualSourceResult(
            sha256: TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
            days: 365,
            holidays: 121,
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    final check = find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey);
    expect(check, findsOneWidget);
    expect(checks, 0, reason: 'Foreground must not silently download.');
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNotNull, reason: 'Explicit success must persist a verified advisory receipt.');
    expect(check, findsNothing, reason: 'Same-day retry must be suppressed.');
    expect(find.textContaining('未安裝 2027 年日曆'), findsOneWidget);
    expect(db.writes, 0);
  });

  testWidgets('B2.14b source failure never records success or writes',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    var checks = 0;
    // Widget tests must not await the platform SharedPreferences channel.
    // Exercise the same production receipt contract with isolated storage.
    String? raw;
    final receiptStore = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; });
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: receiptStore,
        clock: () => DateTime.utc(2026, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          throw const FormatException('tampered bytes');
        },
      ),
    ));
    await tester.pumpAndSettle();
    final check = find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNull, reason: 'Untrusted official source must never persist a receipt.');
    expect(check, findsOneWidget, reason: 'Failure must permit explicit retry.');
    expect(find.textContaining('SHA／年度結構驗證失敗'), findsOneWidget);
    expect(db.writes, 0);
  });

  testWidgets('B2.14b absent current-year authority forbids network check',
      (tester) async {
    final db = _ReadOnlyDb(verified: false);
    var checks = 0;
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        clock: () => DateTime.utc(2026, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          throw StateError('must not be called');
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsNothing);
    expect(checks, 0);
    expect(db.writes, 0);
  });

  testWidgets('B2.14c same-day receipt survives page recreation, zero DB writes',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw, writeRaw: (value) async { raw = value; });
    Widget page() => MaterialApp(home: TaiwanBusinessCalendarStatusPage(
      databaseProvider: () async => db,
      receiptStore: store,
      clock: () => DateTime.utc(2026, 11, 30, 16, 1),
      officialSourceCheck: () async {
        checks++;
        return const TaiwanBusinessCalendarAnnualSourceResult(
          sha256: TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
          days: 365, holidays: 121);
      },
    ));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNotNull);
    expect(db.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsNothing);
    expect(checks, 1);
    expect(db.writes, 0);
  });

  testWidgets('B2.14c failed receipt write allows next-page manual retry',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => null,
      writeRaw: (_) async => throw StateError('storage unavailable'));
    Widget page() => MaterialApp(home: TaiwanBusinessCalendarStatusPage(
      databaseProvider: () async => db,
      receiptStore: store,
      clock: () => DateTime.utc(2026, 11, 30, 16, 1),
      officialSourceCheck: () async {
        checks++;
        return const TaiwanBusinessCalendarAnnualSourceResult(
          sha256: TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
          days: 365, holidays: 121);
      },
    ));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('檢查紀錄未能保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget);
    expect(checks, 1);
    expect(db.writes, 0);
  });
  testWidgets('B2.14d current-year revision swap during GET cannot persist stale receipt',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; });
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => DateTime.utc(2026, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          // Simulate an independently committed full-year revision while
          // official HTTPS verification is in flight. No formal DB writes.
          final metadata = jsonDecode(
              db.current.first['source_revision'] as String)
              as Map<String, dynamic>;
          metadata['revision_sequence'] = 2;
          metadata['sha256'] = List<String>.filled(64, 'b').join();
          final replacement = jsonEncode(metadata);
          for (var i = 0; i < db.current.length; i++) {
            db.current[i] = <String, Object?>{
              ...db.current[i], 'source_revision': replacement,
            };
          }
          return const TaiwanBusinessCalendarAnnualSourceResult(
            sha256: TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
            days: 365, holidays: 121);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget);
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNull, reason: 'Stale source identity must not be persisted.');
    expect(find.textContaining('本年度日曆來源身分已變更'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget, reason: 'A fresh explicit check remains possible.');
    expect(db.writes, 0);
  });

}

/// Read-only synthetic SQLite fixture. No real official year is inferred.
class _ReadOnlyDb implements DatabaseExecutor {
  _ReadOnlyDb({required bool verified, bool partial = false,
      bool nextInstalled = false})
      : current = verified ? _year(2026, partial: partial) : [],
        next = nextInstalled ? _year(2027) : [];

  final List<Map<String, Object?>> current;
  final List<Map<String, Object?>> next;
  int reads = 0;
  int writes = 0;

  static List<Map<String, Object?>> _year(int year, {bool partial = false}) {
    final start = DateTime.utc(year, 1, 1);
    final count = DateTime.utc(year + 1, 1, 1).difference(start).inDays;
    final revision = jsonEncode(<String, Object?>{
      'format_version': 1, 'source_year': year,
      'source_revision': 'SYNTHETIC-TEST-ONLY', 'revision_sequence': 1,
      'source_published_at': '2026-05-21',
      'coverage_start': '$year-01-01', 'coverage_end': '$year-12-31',
      'row_count': count, 'sha256': List<String>.filled(64, 'a').join(),
    });
    return List<Map<String, Object?>>.generate(
      partial ? count - 1 : count,
      (i) {
        final day = start.add(Duration(days: i));
        return <String, Object?>{
          'calendar_date': day.toIso8601String().substring(0, 10),
          'is_business_day': day.weekday <= DateTime.friday ? 1 : 0,
          'day_label': '', 'source_year': year,
          'source_revision': revision,
          'source_url': 'https://www.dgpa.gov.tw/test-only.csv',
          'updated_at': '2026-11-01T00:00:00Z',
        };
      },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #query) {
      reads++;
      final args = invocation.namedArguments[#whereArgs] as List<Object?>?;
      final year = args?.first as int?;
      final rows = year == 2026 ? current : year == 2027 ? next :
          <Map<String, Object?>>[];
      if (args != null && args.length == 3) {
        final start = args[1] as String;
        final end = args[2] as String;
        return Future<List<Map<String, Object?>>>.value(
          rows.where((row) {
            final date = row['calendar_date'] as String;
            return date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
          }).map((row) => <String, Object?>{
            'calendar_date': row['calendar_date'],
            'is_business_day': row['is_business_day'],
          }).toList(),
        );
      }
      return Future<List<Map<String, Object?>>>.value(rows);
    }
    writes++;
    throw StateError('B2.14a foreground eligibility must be read-only');
  }
}
