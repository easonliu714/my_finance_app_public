import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_foreground_notice.dart';
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
