import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_foreground_notice.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_status_page.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_annual_check_receipt.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_annual_source_check.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_official_116_stage.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  Widget harness(
    _ReadOnlyDb db,
    DateTime Function() clock, {
    TaiwanBusinessCalendarAnnualCheckReceiptStore? receiptStore,
  }) => MaterialApp(
    home: Scaffold(
      body: TaiwanBusinessCalendarForegroundNotice(
        databaseProvider: () async => db,
        clock: clock,
        // Never depend on a real platform preferences channel in widget tests.
        receiptStore: receiptStore ??
            TaiwanBusinessCalendarAnnualCheckReceiptStore(
              readRaw: () async => null,
            ),
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

  testWidgets('B2.14f verified same-day receipt suppresses foreground notice '
      'until the current-year digest changes', (tester) async {
    final db = _ReadOnlyDb(verified: true);
    final now = DateTime.utc(2026, 11, 30, 16, 1);
    String? raw;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; },
    );
    await store.writeVerified(
      year: 2026,
      digest: List<String>.filled(64, 'a').join(),
      checkedAt: now,
    );
    await tester.pumpWidget(harness(db, () => now, receiptStore: store));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsNothing, reason: 'Verified same-day manual check suppresses notice.');
    expect(db.writes, 0);

    // Simulate a newly installed, independently verified current-year
    // revision. The old advisory receipt cannot suppress the new notice.
    final metadata = jsonDecode(db.current.first['source_revision'] as String)
        as Map<String, dynamic>;
    metadata['sha256'] = List<String>.filled(64, 'b').join();
    final replacement = jsonEncode(metadata);
    for (var i = 0; i < db.current.length; i++) {
      db.current[i] = <String, Object?>{
        ...db.current[i],
        'source_revision': replacement,
      };
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsOneWidget);
    expect(db.writes, 0);
  });

  testWidgets('B2.14f corrupt or unavailable advisory receipt never hides '
      'the manual foreground notice', (tester) async {
    final db = _ReadOnlyDb(verified: true);
    final now = DateTime.utc(2026, 11, 30, 16, 1);
    final corrupt = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => '{corrupt',
    );
    await tester.pumpWidget(harness(db, () => now, receiptStore: corrupt));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsOneWidget);
    final unavailable = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => throw StateError('preferences unavailable'),
    );
    await tester.pumpWidget(harness(db, () => now, receiptStore: unavailable));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsOneWidget);
    expect(db.writes, 0);
  });

  testWidgets('B2.14g returning from verified manual check immediately '
      'hides foreground notice without lifecycle resume or SQLite writes',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    final now = DateTime.utc(2026, 11, 30, 16, 1);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; },
    );
    final router = GoRouter(routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TaiwanBusinessCalendarForegroundNotice(
            databaseProvider: () async => db,
            clock: () => now,
            receiptStore: store,
          ),
        ),
      ),
      GoRoute(
        name: TaiwanBusinessCalendarStatusPage.routeName,
        path: TaiwanBusinessCalendarStatusPage.routePath,
        builder: (context, state) => TaiwanBusinessCalendarStatusPage(
          databaseProvider: () async => db,
          receiptStore: store,
          clock: () => now,
          officialSourceCheck: () async {
            checks++;
            return const TaiwanBusinessCalendarAnnualSourceResult(
              sha256: TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
              days: 365,
              holidays: 121,
            );
          },
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsOneWidget);
    await tester.tap(find.text('查看日曆'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNotNull);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsNothing, reason: 'Route pop must refresh the saved receipt.');
    expect(checks, 1, reason: 'Foreground must never repeat official GET.');
    expect(db.writes, 0);
  });

  testWidgets('B2.14g failed manual check leaves notice eligible on route pop',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    final now = DateTime.utc(2026, 11, 30, 16, 1);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; },
    );
    final router = GoRouter(routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TaiwanBusinessCalendarForegroundNotice(
            databaseProvider: () async => db,
            clock: () => now,
            receiptStore: store,
          ),
        ),
      ),
      GoRoute(
        name: TaiwanBusinessCalendarStatusPage.routeName,
        path: TaiwanBusinessCalendarStatusPage.routePath,
        builder: (context, state) => TaiwanBusinessCalendarStatusPage(
          databaseProvider: () async => db,
          receiptStore: store,
          clock: () => now,
          officialSourceCheck: () async {
            checks++;
            throw const FormatException('untrusted official source');
          },
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看日曆'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNull);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsOneWidget, reason: 'Failed source check must not hide notice.');
    expect(db.writes, 0);
  });

  testWidgets('B2.14k resume refreshes newly installed current-year authority '
      'without automatic network or SQLite writes', (tester) async {
    final db = _ReadOnlyDb(verified: false);
    var checks = 0;
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: TaiwanBusinessCalendarAnnualCheckReceiptStore(
          readRaw: () async => null,
        ),
        clock: () => DateTime.utc(2026, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          throw StateError('resume must not invoke official GET');
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsNothing);
    db.current.addAll(_ReadOnlyDb._year(2026));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget, reason: 'Resume must refresh independent installed authority.');
    expect(checks, 0);
    expect(db.writes, 0);
  });

  testWidgets('B2.14k resume after Taipei midnight restores manual check '
      'without automatic GET or SQLite writes', (tester) async {
    final db = _ReadOnlyDb(verified: true);
    var now = DateTime.utc(2026, 11, 30, 16, 1);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; },
    );
    await store.writeVerified(
      year: 2026,
      digest: List<String>.filled(64, 'a').join(),
      checkedAt: now,
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => now,
        officialSourceCheck: () async {
          checks++;
          throw StateError('resume must not invoke official GET');
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsNothing, reason: 'Verified same-day receipt suppresses duplicate check.');
    now = DateTime.utc(2026, 12, 1, 16, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget, reason: 'Yesterday receipt must not suppress today.');
    expect(checks, 0);
    expect(db.writes, 0);
  });

  testWidgets('B2.14l resume invalidates yesterday saved-today claim '
      'without GET or SQLite writes', (tester) async {
    final db = _ReadOnlyDb(verified: true);
    var now = DateTime.utc(2026, 11, 30, 16, 1);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; },
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => now,
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
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('本機當日檢查紀錄已保存'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('本機當日檢查紀錄已保存'), findsOneWidget,
        reason: 'Same-day verified receipt remains truthful.');
    now = DateTime.utc(2026, 12, 1, 16, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('本機當日檢查紀錄已保存'), findsNothing);
    expect(find.textContaining('先前檢查紀錄不適用'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget);
    expect(checks, 1, reason: 'Resume must never invoke official GET.');
    expect(db.writes, 0);
  });

  testWidgets('B2.14l independent calendar revision revokes old success '
      'without automatic GET or SQLite writes', (tester) async {
    final db = _ReadOnlyDb(verified: true);
    final now = DateTime.utc(2026, 11, 30, 16, 1);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async { raw = value; },
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => now,
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
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('本機當日檢查紀錄已保存'), findsOneWidget);
    final metadata = jsonDecode(
        db.current.first['source_revision'] as String) as Map<String, dynamic>;
    metadata['revision_sequence'] = 2;
    metadata['sha256'] = List<String>.filled(64, 'b').join();
    final replacement = jsonEncode(metadata);
    for (var i = 0; i < db.current.length; i++) {
      db.current[i] = <String, Object?>{
        ...db.current[i],
        'source_revision': replacement,
      };
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('本機當日檢查紀錄已保存'), findsNothing);
    expect(find.textContaining('先前檢查紀錄不適用'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget);
    expect(checks, 1);
    expect(db.writes, 0);
  });

  // B2.14m: the first preferences read completes after Taipei midnight.
  // The stale Dec-1 receipt must not suppress the Dec-2 manual action.
  testWidgets('B2.14m read-only status crossing midnight retries new day',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    final dec1 = DateTime.utc(2026, 11, 30, 16, 1);
    var now = dec1;
    String? raw;
    var reads = 0;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async {
        if (++reads == 1) now = DateTime.utc(2026, 12, 1, 16, 1);
        return raw;
      },
      writeRaw: (value) async { raw = value; },
    );
    await store.writeVerified(
      year: 2026,
      digest: List<String>.filled(64, 'a').join(),
      checkedAt: dec1,
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => now,
        officialSourceCheck: () async {
          checks++;
          throw StateError('read-only refresh must not GET');
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(reads, greaterThanOrEqualTo(2));
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget);
    expect(find.textContaining('今日已檢查'), findsNothing);
    expect(find.textContaining('2026 年：'), findsOneWidget);
    expect(checks, 0);
    expect(db.writes, 0);
  });

  // B2.14m: New Year rollover must refresh BOTH displayed year labels,
  // not merely invalidate the old same-day receipt.
  testWidgets('B2.14m read-only New Year rollover rebinds year labels',
      (tester) async {
    final db = _ReadOnlyDb(verified: true, nextInstalled: true);
    var now = DateTime.utc(2026, 12, 31, 15, 59);
    var reads = 0;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async {
        if (++reads == 1) now = DateTime.utc(2026, 12, 31, 16, 1);
        return null;
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => now,
        officialSourceCheck: () async {
          checks++;
          throw StateError('read-only rollover must not GET');
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026 年：'), findsNothing);
    expect(find.textContaining('2027 年：'), findsOneWidget);
    expect(find.textContaining('2028 年：'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsNothing);
    expect(checks, 0);
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
    // B2.14e: failed advisory storage must not suppress a second explicit
    // check in the SAME mounted page; no official data or SQLite is written.
    final manualCheck = find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey);
    expect(manualCheck, findsOneWidget);
    await tester.tap(manualCheck);
    await tester.pumpAndSettle();
    expect(checks, 2, reason: 'Failed receipt must permit same-page manual retry.');
    expect(find.textContaining('檢查紀錄未能保存'), findsOneWidget);
    expect(db.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget);
    expect(checks, 2);
    expect(db.writes, 0);
  });
  testWidgets('B2.14h unverified receipt readback never suppresses manual retry',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    var checks = 0;
    var writes = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      // A nominally successful write without verifiable read-back is HOLD.
      readRaw: () async => null,
      writeRaw: (_) async { writes++; },
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => DateTime.utc(2026, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          return const TaiwanBusinessCalendarAnnualSourceResult(
            sha256: TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
            days: 365, holidays: 121,
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(writes, 1);
    expect(find.textContaining('檢查紀錄未能保存'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget, reason: 'Unverified receipt cannot suppress manual retry.');
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(db.writes, 0);
  });

  testWidgets('B2.14h revision swap during receipt write restores manual action',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async {
        raw = value;
        // Simulate a separately verified current-year revision after GET.
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
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => DateTime.utc(2026, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          return const TaiwanBusinessCalendarAnnualSourceResult(
            sha256: TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
            days: 365, holidays: 121,
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNotNull);
    // B2.14i: a revision changed during advisory persistence cannot be
    // presented as a successful current-year durable source check.
    expect(find.textContaining('當日檢查紀錄已保存'), findsNothing);
    expect(find.textContaining('或未能確認目前年度來源'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget, reason: 'New digest invalidates old advisory receipt.');
    expect(db.writes, 0);
  });

  testWidgets('B2.14j midnight during advisory write cannot claim today saved',
      (tester) async {
    final db = _ReadOnlyDb(verified: true);
    var now = DateTime.utc(2026, 11, 30, 16, 1); // Taipei Dec 1, 00:01.
    String? raw;
    var checks = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw,
      writeRaw: (value) async {
        raw = value;
        // A slow local preferences write crosses Taipei midnight.
        now = DateTime.utc(2026, 12, 1, 16, 1); // Taipei Dec 2, 00:01.
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: store,
        clock: () => now,
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
    await tester.tap(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(raw, isNotNull, reason: 'Yesterday receipt remains advisory only.');
    expect(find.textContaining('當日檢查紀錄已保存'), findsNothing,
        reason: 'Yesterday must never be presented as today after midnight.');
    expect(find.textContaining('檢查紀錄未能保存'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsOneWidget, reason: 'New Taipei day allows explicit retry.');
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


  // B2.14n: annualUpdateDecision is intentionally year-generic, but the
  // production manual GET and SHA are pinned to ROC116 (2027) only.
  testWidgets('B2.14n future-year foreground cannot reuse ROC116 source',
      (tester) async {
    final db = _ReadOnlyDb(verified: false);
    db.next.addAll(_ReadOnlyDb._year(2027));
    await tester.pumpWidget(
        harness(db, () => DateTime.utc(2027, 11, 30, 16, 1)));
    await tester.pumpAndSettle();
    expect(find.byKey(TaiwanBusinessCalendarForegroundNotice.noticeKey),
        findsNothing,
        reason: '2028 has no pinned source; do not advertise a 116 check.');
    expect(db.reads, greaterThan(0));
    expect(db.writes, 0);
  });

  testWidgets('B2.14n future-year status blocks stale ROC116 manual GET',
      (tester) async {
    final db = _ReadOnlyDb(verified: false);
    db.next.addAll(_ReadOnlyDb._year(2027));
    var checks = 0;
    await tester.pumpWidget(MaterialApp(
      home: TaiwanBusinessCalendarStatusPage(
        databaseProvider: () async => db,
        receiptStore: TaiwanBusinessCalendarAnnualCheckReceiptStore(
          readRaw: () async => null,
        ),
        clock: () => DateTime.utc(2027, 11, 30, 16, 1),
        officialSourceCheck: () async {
          checks++;
          throw StateError('Unpinned 2028 source must not GET ROC116');
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('2027 年：'), findsOneWidget);
    expect(find.textContaining('2028 年：'), findsOneWidget);
    expect(find.textContaining('尚未釘選 2028 年官方來源'), findsOneWidget);
    expect(find.byKey(TaiwanBusinessCalendarStatusPage.annualCheckKey),
        findsNothing);
    expect(checks, 0);
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
