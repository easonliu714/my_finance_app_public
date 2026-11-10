import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const codec = TaiwanBusinessCalendarPackageCodec();
  const service = TaiwanBusinessCalendarPackageService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('installs one year transactionally and reports coverage', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final package = await _package(codec, year: 2028, sequence: 1);

    final result = await service.install(
      db,
      package,
      importedAt: DateTime.utc(2027, 7, 1),
    );
    final status = await service.status(db, 2028);

    expect(result.disposition, CalendarPackageInstallDisposition.installed);
    expect(await db.query('taiwan_business_calendar_days'), hasLength(366));
    expect(status, isNotNull);
    expect(status!.start, '2028-01-01');
    expect(status.end, '2028-12-31');
    expect(status.rowCount, 366);
    expect(status.revision, 'DGPA-2028-test-r1');
    expect(status.sequence, 1);
    expect(status.digest, package.digest);
    expect(status.isContiguous, isTrue);
  });

  test('identical revision is idempotent', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final package = await _package(codec, year: 2028, sequence: 1);

    await service.install(db, package);
    final second = await service.install(db, package);

    expect(second.disposition, CalendarPackageInstallDisposition.unchanged);
    expect(await db.query('taiwan_business_calendar_days'), hasLength(366));
  });

  test('newer revision replaces only its year and preserves other years', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyDay(db, year: 2027, date: '2027-12-31');
    final first = await _package(codec, year: 2028, sequence: 1);
    final second = await _package(
      codec,
      year: 2028,
      sequence: 2,
      closedDate: '2028-07-03',
    );

    await service.install(db, first);
    await service.install(db, second);

    expect(
      await db.query(
        'taiwan_business_calendar_days',
        where: 'source_year = 2027',
      ),
      hasLength(1),
    );
    final changed = await db.query(
      'taiwan_business_calendar_days',
      where: 'calendar_date = ?',
      whereArgs: <Object?>['2028-07-03'],
    );
    expect((changed.single['is_business_day'] as num).toInt(), 0);
    expect((await service.status(db, 2028))!.sequence, 2);
  });

  test('older and equal conflicting revisions are rejected', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final current = await _package(codec, year: 2028, sequence: 2);
    final older = await _package(codec, year: 2028, sequence: 1);
    final conflict = await _package(
      codec,
      year: 2028,
      sequence: 2,
      closedDate: '2028-07-03',
    );
    await service.install(db, current);

    await expectLater(
      service.install(db, older),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    await expectLater(
      service.install(db, conflict),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    expect((await service.status(db, 2028))!.digest, current.digest);
  });

  test('legacy bundled rows can be upgraded by a versioned package', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyYear(db, 2028);
    final package = await _package(codec, year: 2028, sequence: 1);

    final result = await service.install(db, package);

    expect(result.disposition, CalendarPackageInstallDisposition.installed);
    expect((await service.status(db, 2028))!.sequence, 1);
  });

  test('B2 damaged package metadata is not silently treated as legacy', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final newer = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    // Simulate a damaged metadata envelope in every row. A single shared
    // invalid JSON-shaped revision previously passed the legacy heuristic.
    const damaged = '{"format_version":1,"broken":true}';
    await db.update(
      'taiwan_business_calendar_days',
      <String, Object?>{'source_revision': damaged},
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );

    await expectLater(
      service.install(db, newer),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final rows = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(rows, hasLength(366));
    expect(rows.every((row) => row['source_revision'] == damaged), isTrue);
    expect(rows.every((row) => row['source_url'] == original.sourceUrl), isTrue);
  });

  test('B2.15 damaged legacy flags and labels cannot be promoted or erased', () async {
    // Old installed calendar schemas did not necessarily enforce modern
    // SQLite CHECK/NOT NULL constraints. A complete date range alone is
    // insufficient authority to overwrite corrupted legacy data.
    for (final corruption in <Map<String, Object?>>[
      <String, Object?>{'is_business_day': 2},
      <String, Object?>{'is_business_day': 'invalid'},
      <String, Object?>{'day_label': null},
    ]) {
      final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
      try {
        await _insertLegacyYear(db, 2028);
        await db.update(
          'taiwan_business_calendar_days',
          corruption,
          where: 'calendar_date = ?',
          whereArgs: <Object?>['2028-07-01'],
        );
        final before = await db.query('taiwan_business_calendar_days',
            where: 'source_year = ?', whereArgs: <Object?>[2028],
            orderBy: 'calendar_date ASC');
        final replacement = await _package(codec, year: 2028, sequence: 1);
        expect((await service.status(db, 2028))!.isContiguous, isFalse,
            reason: 'Corrupt legacy row must not be trusted: $corruption');
        await expectLater(
          service.install(db, replacement),
          throwsA(isA<CalendarPackageConflictException>()),
        );
        final after = await db.query('taiwan_business_calendar_days',
            where: 'source_year = ?', whereArgs: <Object?>[2028],
            orderBy: 'calendar_date ASC');
        expect(after, equals(before),
            reason: 'Failed promotion must preserve every original row');
      } finally {
        await db.close();
      }
    }
  });

  test('B2.15 damaged installed day label cannot authorize replacement', () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    try {
      final original = await _package(codec, year: 2028, sequence: 1);
      final newer = await _package(codec, year: 2028, sequence: 2);
      await service.install(db, original);
      await db.update('taiwan_business_calendar_days',
          <String, Object?>{'day_label': null},
          where: 'calendar_date = ?',
          whereArgs: <Object?>['2028-07-01']);
      final before = await db.query('taiwan_business_calendar_days',
          where: 'source_year = ?', whereArgs: <Object?>[2028],
          orderBy: 'calendar_date ASC');
      final status = await service.status(db, 2028);
      expect(status!.isContiguous, isFalse);
      expect(status.sequence, 0);
      await expectLater(service.install(db, newer),
          throwsA(isA<CalendarPackageConflictException>()));
      final after = await db.query('taiwan_business_calendar_days',
          where: 'source_year = ?', whereArgs: <Object?>[2028],
          orderBy: 'calendar_date ASC');
      expect(after, equals(before));
    } finally {
      await db.close();
    }
  });


  test('B2.16 new metadata detects valid-looking day tamper without writes', () async {
    for (final mutation in <Map<String, Object?>>[
      <String, Object?>{'is_business_day': 0},
      <String, Object?>{'day_label': 'altered but valid text'},
    ]) {
      final db = await _openCalendarDatabase();
      try {
        final original = await _package(codec, year: 2028, sequence: 1);
        final newer = await _package(codec, year: 2028, sequence: 2);
        await service.install(db, original);
        final before = await service.status(db, 2028);
        expect(before!.digest, original.digest);
        expect(before.isContiguous, isTrue);
        await db.update(
          'taiwan_business_calendar_days', mutation,
          where: 'calendar_date = ?', whereArgs: <Object?>['2028-07-03'],
        );
        final corrupted = await db.query('taiwan_business_calendar_days',
            where: 'source_year = ?', whereArgs: <Object?>[2028],
            orderBy: 'calendar_date ASC');
        final status = await service.status(db, 2028);
        expect(status!.isContiguous, isFalse,
            reason: 'Valid-type tamper must not retain verified authority');
        expect(status.sequence, 0);
        expect(status.digest, isEmpty);
        await expectLater(service.install(db, newer),
            throwsA(isA<CalendarPackageConflictException>()));
        final retained = await db.query('taiwan_business_calendar_days',
            where: 'source_year = ?', whereArgs: <Object?>[2028],
            orderBy: 'calendar_date ASC');
        expect(retained, equals(corrupted),
            reason: 'Rejected replacement preserves every stored row');
      } finally {
        await db.close();
      }
    }
  });

  test('B2.16 historical metadata remains readable without generated_at', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    final legacy = Map<String, Object?>.from(
      jsonDecode(original.storedMetadata.encode()) as Map,
    )..remove('generated_at');
    await db.update('taiwan_business_calendar_days',
        <String, Object?>{'source_revision': jsonEncode(legacy)},
        where: 'source_year = ?', whereArgs: <Object?>[2028]);
    final status = await service.status(db, 2028);
    expect(status!.sequence, 1);
    expect(status.isContiguous, isTrue);
    // Legacy structural compatibility is not cryptographic row verification.
  });

  test('B2.17 structural-only current year cannot authorize December trigger',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    // Simulate a historical installed envelope: its digest cannot be
    // recomputed without generated_at. A valid 0/1 row tamper is invisible
    // to the structural-only checks and must never authorize a trigger.
    final legacy = Map<String, Object?>.from(
      jsonDecode(original.storedMetadata.encode()) as Map,
    )..remove('generated_at');
    await db.update('taiwan_business_calendar_days',
        <String, Object?>{'source_revision': jsonEncode(legacy)},
        where: 'source_year = ?', whereArgs: <Object?>[2028]);
    await db.update('taiwan_business_calendar_days',
        <String, Object?>{
          'is_business_day': 0,
          'day_label': 'valid-type-tamper',
        },
        where: 'calendar_date = ?', whereArgs: <Object?>['2028-12-04']);
    final status = await service.status(db, 2028);
    expect(status!.isContiguous, isTrue);
    expect(status.sequence, 1);
    expect(status.hasCanonicalRowDigest, isFalse);
    final before = await db.query('taiwan_business_calendar_days',
        where: 'source_year = ?', whereArgs: <Object?>[2028],
        orderBy: 'calendar_date ASC');
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.currentYearNotVerified,
    );
    expect(await db.query('taiwan_business_calendar_days',
        where: 'source_year = ?', whereArgs: <Object?>[2028],
        orderBy: 'calendar_date ASC'), equals(before),
        reason: 'Read-only fail-closed check cannot rewrite legacy rows');
  });

  test('B2.17 structural-only next year cannot suppress official check',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await service.install(db, await _package(codec, year: 2028, sequence: 1));
    final next = await _package(codec, year: 2029, sequence: 1);
    await service.install(db, next);
    final legacy = Map<String, Object?>.from(
      jsonDecode(next.storedMetadata.encode()) as Map,
    )..remove('generated_at');
    await db.update('taiwan_business_calendar_days',
        <String, Object?>{'source_revision': jsonEncode(legacy)},
        where: 'source_year = ?', whereArgs: <Object?>[2029]);
    await db.update('taiwan_business_calendar_days',
        <String, Object?>{'day_label': 'valid-type-tamper'},
        where: 'calendar_date = ?', whereArgs: <Object?>['2029-07-02']);
    final current = await service.status(db, 2028);
    final historical = await service.status(db, 2029);
    expect(current!.hasCanonicalRowDigest, isTrue);
    expect(historical!.isContiguous, isTrue);
    expect(historical.hasCanonicalRowDigest, isFalse);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.nextYearUntrusted,
    );
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before),
        reason: 'Untrusted next-year rows remain retained for audit');
  });

  test('B2 incomplete legacy year is not upgraded or overwritten', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyDay(db, year: 2028, date: '2028-07-01');
    final replacement = await _package(codec, year: 2028, sequence: 1);

    await expectLater(
      service.install(db, replacement),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final rows = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(rows, hasLength(1));
    expect(rows.single['calendar_date'], '2028-07-01');
    expect(rows.single['source_revision'], 'DGPA-legacy-2028');
  });

  test('B2.1 structurally forged stored metadata cannot replace a year',
      () async {
    for (final corruption in <String, Object?>{
      'source_year': 2027,
      'sha256': 'invalid-digest',
      'revision_sequence': 0,
    }.entries) {
      final db = await _openCalendarDatabase();
      final original = await _package(codec, year: 2028, sequence: 1);
      final newer = await _package(codec, year: 2028, sequence: 2);
      await service.install(db, original);
      final rowsBefore = await db.query('taiwan_business_calendar_days',
          where: 'source_year = ?', whereArgs: <Object?>[2028]);
      final metadata = Map<String, Object?>.from(jsonDecode(
        rowsBefore.first['source_revision']! as String,
      ) as Map);
      metadata[corruption.key] = corruption.value;
      final damaged = jsonEncode(metadata);
      await db.update(
        'taiwan_business_calendar_days',
        <String, Object?>{'source_revision': damaged},
        where: 'source_year = ?',
        whereArgs: <Object?>[2028],
      );

      await expectLater(
        service.install(db, newer),
        throwsA(isA<CalendarPackageConflictException>()),
        reason: 'Corrupt ${corruption.key} must not be promoted to legacy.',
      );
      final retained = await db.query('taiwan_business_calendar_days',
          where: 'source_year = ?', whereArgs: <Object?>[2028]);
      expect(retained, hasLength(366));
      expect(retained.every((row) => row['source_revision'] == damaged),
          isTrue);
      expect(retained.every((row) => row['source_url'] == original.sourceUrl),
          isTrue);
      await db.close();
    }
  });

  test('B2.1 partial legacy status is not a complete annual coverage',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyDay(db, year: 2028, date: '2028-07-01');

    final status = await service.status(db, 2028);

    expect(status, isNotNull);
    expect(status!.rowCount, 1);
    expect(status.isContiguous, isFalse);
    expect(status.sequence, 0);
  });


  test('B2.3 corrupted stored official URL rejects replacement and status',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final newer = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    const attackerUrl = 'https://www.dgpa.gov.tw.attacker.example/calendar.csv';
    await db.update(
      'taiwan_business_calendar_days',
      <String, Object?>{'source_url': attackerUrl},
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );

    final status = await service.status(db, 2028);
    expect(status, isNotNull);
    expect(status!.isContiguous, isFalse);
    await expectLater(
      service.install(db, newer),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final retained = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(retained, hasLength(366));
    expect(retained.every((row) => row['source_url'] == attackerUrl), isTrue);
    expect(retained.every((row) =>
        row['source_revision'] == original.storedMetadata.encode()), isTrue);
  });

  test('B2.3 complete legacy year with unapproved URL cannot be promoted',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await _insertLegacyYear(db, 2028);
    const attackerUrl = 'https://attacker.example/calendar.csv';
    await db.update(
      'taiwan_business_calendar_days',
      <String, Object?>{'source_url': attackerUrl},
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    final replacement = await _package(codec, year: 2028, sequence: 1);

    expect((await service.status(db, 2028))!.isContiguous, isFalse);
    await expectLater(
      service.install(db, replacement),
      throwsA(isA<CalendarPackageConflictException>()),
    );
    final retained = await db.query(
      'taiwan_business_calendar_days',
      where: 'source_year = ?',
      whereArgs: <Object?>[2028],
    );
    expect(retained, hasLength(366));
    expect(retained.every((row) => row['source_url'] == attackerUrl), isTrue);
    expect(retained.every((row) =>
        row['source_revision'] == 'DGPA-legacy-2028'), isTrue);
  });

  test('B2.5 concurrent annual refreshes cannot downgrade verified LKG',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final baseline = await _package(codec, year: 2028, sequence: 1);
    final latest = await _package(
      codec, year: 2028, sequence: 3, closedDate: '2028-07-03',
    );
    final stale = await _package(
      codec, year: 2028, sequence: 2, closedDate: '2028-07-04',
    );
    await service.install(db, baseline);

    // Queue a newer and stale writer concurrently. The second writer must
    // observe the first committed revision inside its own transaction.
    final outcomes = await Future.wait<Object>(<Future<Object>>[
      service.install(db, latest).then<Object>(
        (value) => value, onError: (Object error) => error,
      ),
      service.install(db, stale).then<Object>(
        (value) => value, onError: (Object error) => error,
      ),
    ]);
    expect(outcomes.first, isA<CalendarPackageInstallResult>());
    expect(
      (outcomes.first as CalendarPackageInstallResult).disposition,
      CalendarPackageInstallDisposition.installed,
    );
    expect(outcomes.last, isA<CalendarPackageConflictException>());

    final status = await service.status(db, 2028);
    expect(status, isNotNull);
    expect(status!.isContiguous, isTrue);
    expect(status.sequence, 3);
    expect(status.digest, latest.digest);
    expect(status.rowCount, 366);
    final rows = await db.query('taiwan_business_calendar_days',
        where: 'source_year = ?', whereArgs: <Object?>[2028]);
    expect(rows, hasLength(366));
    expect(rows.every((row) =>
        row['source_revision'] == latest.storedMetadata.encode()), isTrue);
    expect(rows.singleWhere((row) => row['calendar_date'] == '2028-07-03')
        ['is_business_day'], 0);
    expect(rows.singleWhere((row) => row['calendar_date'] == '2028-07-04')
        ['is_business_day'], 1);
  });

  test('failed replacement rolls back the original year', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final first = await _package(codec, year: 2028, sequence: 1);
    final second = await _package(
      codec,
      year: 2028,
      sequence: 2,
      closedDate: '2028-07-03',
    );
    await service.install(db, first);
    await db.execute('''
      CREATE TRIGGER block_calendar_insert
      BEFORE INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2028-07-01'
      BEGIN
        SELECT RAISE(ABORT, 'blocked for rollback test');
      END
    ''');

    await expectLater(
      service.install(db, second),
      throwsA(isA<DatabaseException>()),
    );

    final status = await service.status(db, 2028);
    expect(status!.sequence, 1);
    expect(status.digest, first.digest);
    expect(status.rowCount, 366);
  });

  test('B2.4 official December trigger uses installed workday, not weekends',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    // Synthetic fixture: Friday Dec 1 is an official-style holiday, so the
    // first workday is Monday Dec 4. No real DGPA data is asserted here.
    await service.install(db, await _package(
      codec, year: 2028, sequence: 1, closedDate: '2028-12-01',
    ));
    final before = await db.query('taiwan_business_calendar_days');
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 11, 30, 15, 59)),
      CalendarAnnualUpdateDecision.outsideDecember,
    );
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 3, 15, 59)),
      CalendarAnnualUpdateDecision.beforeFirstBusinessDay,
    );
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 3, 16)),
      CalendarAnnualUpdateDecision.checkOfficialSource,
    );
    expect(
      await service.annualUpdateDecision(
        db, DateTime.utc(2028, 12, 4),
        lastCheckedAt: DateTime.utc(2028, 12, 3, 16, 1),
      ),
      CalendarAnnualUpdateDecision.checkedToday,
    );
    expect(await db.query('taiwan_business_calendar_days'), before,
        reason: 'A foreground eligibility check must not mutate SQLite.');
  });

  test('B2.18 future-dated same-Taipei-day receipt never suppresses check',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await service.install(db, await _package(codec, year: 2028, sequence: 1));
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    final now = DateTime.utc(2028, 12, 4, 1);

    // Both times are Dec 4 in Taipei; only the earlier check is eligible.
    expect(
      await service.annualUpdateDecision(db, now,
          lastCheckedAt: DateTime.utc(2028, 12, 4, 2)),
      CalendarAnnualUpdateDecision.checkOfficialSource,
    );
    expect(
      await service.annualUpdateDecision(db, now,
          lastCheckedAt: DateTime.utc(2028, 12, 4, 0, 30)),
      CalendarAnnualUpdateDecision.checkedToday,
    );
    // 15:59Z Dec 3 is still Dec 3 in Taipei, before the local midnight.
    expect(
      await service.annualUpdateDecision(db, now,
          lastCheckedAt: DateTime.utc(2028, 12, 3, 15, 59)),
      CalendarAnnualUpdateDecision.checkOfficialSource,
    );
    expect(
      await service.annualUpdateDecision(db, now),
      CalendarAnnualUpdateDecision.checkOfficialSource,
    );
    expect(
      await db.query('taiwan_business_calendar_days',
          orderBy: 'calendar_date ASC'),
      equals(before),
      reason: 'Advisory receipt checks must not write installed LKG rows.',
    );
  });

  test('B2.4 missing, legacy or corrupt years never authorize update',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2028, 12, 4);
    expect(await service.annualUpdateDecision(db, now),
        CalendarAnnualUpdateDecision.currentYearNotVerified);
    await _insertLegacyYear(db, 2028);
    expect(await service.annualUpdateDecision(db, now),
        CalendarAnnualUpdateDecision.currentYearNotVerified);
    await service.install(db, await _package(codec, year: 2028, sequence: 1));
    await _insertLegacyDay(db, year: 2029, date: '2029-01-01');
    expect(await service.annualUpdateDecision(db, now),
        CalendarAnnualUpdateDecision.nextYearUntrusted);
    expect(await db.query('taiwan_business_calendar_days',
        where: 'source_year = ?', whereArgs: <Object?>[2029]), hasLength(1));
  });

  test('B2.4 fully installed next year suppresses duplicate source checks',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    await service.install(db, await _package(codec, year: 2028, sequence: 1));
    await service.install(db, await _package(codec, year: 2029, sequence: 1));
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.nextYearInstalled,
    );
    expect((await service.status(db, 2029))!.rowCount, 365);
    expect((await service.status(db, 2029))!.hasCanonicalRowDigest, isTrue);
  });

}

// Simulate an older on-device calendar table without current constraints.
// This is isolated in-memory SQLite; it never opens a production database.
Future<Database> _openLegacyCalendarDatabaseWithoutModernConstraints() async {
  final db = await openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE taiwan_business_calendar_days (
      calendar_date TEXT PRIMARY KEY,
      is_business_day INTEGER,
      day_label TEXT,
      source_year INTEGER NOT NULL,
      source_revision TEXT NOT NULL,
      source_url TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  return db;
}

Future<Database> _openCalendarDatabase() async {
  final db = await openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE taiwan_business_calendar_days (
      calendar_date TEXT PRIMARY KEY,
      is_business_day INTEGER NOT NULL,
      day_label TEXT NOT NULL DEFAULT '',
      source_year INTEGER NOT NULL,
      source_revision TEXT NOT NULL,
      source_url TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (is_business_day IN (0, 1))
    )
  ''');
  return db;
}

Future<TaiwanBusinessCalendarYearPackage> _package(
  TaiwanBusinessCalendarPackageCodec codec, {
  required int year,
  required int sequence,
  String? closedDate,
}) {
  return codec.build(
    sourceYear: year,
    sourceRevision: 'DGPA-$year-test-r$sequence',
    revisionSequence: sequence,
    sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
    sourcePublishedAt: '${year - 1}-06-30',
    generatedAt: '${year - 1}-07-01T00:00:00.000Z',
    days: _daysForYear(year, closedDate: closedDate),
  );
}

List<TaiwanBusinessCalendarPackageDay> _daysForYear(
  int year, {
  String? closedDate,
}) {
  final days = <TaiwanBusinessCalendarPackageDay>[];
  var cursor = DateTime.utc(year, 1, 1);
  final end = DateTime.utc(year + 1, 1, 1);
  while (cursor.isBefore(end)) {
    final key = _dateKey(cursor);
    final weekend = cursor.weekday == DateTime.saturday ||
        cursor.weekday == DateTime.sunday;
    final closed = weekend || key == closedDate;
    days.add(
      TaiwanBusinessCalendarPackageDay(
        dateKey: key,
        isBusinessDay: !closed,
        label: closed ? 'closed' : '',
      ),
    );
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

Future<void> _insertLegacyDay(
  Database db, {
  required int year,
  required String date,
}) {
  return db.insert('taiwan_business_calendar_days', <String, Object?>{
    'calendar_date': date,
    'is_business_day': 0,
    'day_label': 'legacy',
    'source_year': year,
    'source_revision': 'DGPA-legacy-$year',
    'source_url': 'https://www.dgpa.gov.tw/informationlist?uid=41',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
}

Future<void> _insertLegacyYear(Database db, int year) async {
  final batch = db.batch();
  for (final day in _daysForYear(year)) {
    batch.insert('taiwan_business_calendar_days', <String, Object?>{
      'calendar_date': day.dateKey,
      'is_business_day': day.isBusinessDay ? 1 : 0,
      'day_label': day.label,
      'source_year': year,
      'source_revision': 'DGPA-legacy-$year',
      'source_url': 'https://www.dgpa.gov.tw/informationlist?uid=41',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
  }
  await batch.commit(noResult: true);
}

String _dateKey(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)}';
}
