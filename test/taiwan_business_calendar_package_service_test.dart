import 'dart:convert';
import 'dart:typed_data';

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

  test('B2.28 corrupt legacy timestamp cannot authorize year replacement',
      () async {
    // Complete legacy coverage is insufficient if a later SQLite row has
    // an invalid storage class or timestamp; preserve every original row.
    for (final corruption in <Object>[
      // sqflite FFI binds SQLite BLOBs from Uint8List, not List<int>.
      Uint8List.fromList(<int>[1, 2]),
      'not-a-timestamp',
      '',
    ]) {
      final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
      try {
        await _insertLegacyYear(db, 2028);
        await db.update(
          'taiwan_business_calendar_days',
          <String, Object?>{'updated_at': corruption},
          where: 'calendar_date = ?',
          whereArgs: <Object?>['2028-07-03'],
        );
        final before = await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC');
        final status = await service.status(db, 2028);
        expect(status, isNotNull);
        expect(status!.isContiguous, isFalse,
            reason: 'Corrupt legacy timestamp must revoke upgrade authority');
        final replacement = await _package(codec, year: 2028, sequence: 1);
        await expectLater(service.install(db, replacement),
            throwsA(isA<CalendarPackageConflictException>()));
        expect(await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC'), equals(before),
            reason: 'Rejected legacy promotion must preserve every row');
      } finally {
        await db.close();
      }
    }
  });

  test('B2.28 valid legacy timestamps still permit an upgrade', () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    addTearDown(db.close);
    await _insertLegacyYear(db, 2028);
    final original = await db.query('taiwan_business_calendar_days',
        where: 'source_year = ?', whereArgs: <Object?>[2028]);
    expect(original, hasLength(366));
    expect((await service.status(db, 2028))!.isContiguous, isTrue);
    final replacement = await _package(codec, year: 2028, sequence: 1);
    final result = await service.install(db, replacement);
    expect(result.disposition, CalendarPackageInstallDisposition.installed);
    final verified = await service.status(db, 2028);
    expect(verified!.hasCanonicalRowDigest, isTrue);
    expect(verified.digest, replacement.digest);
    expect(verified.rowCount, original.length);
  });

  test('B2.35 normalized legacy timestamps cannot authorize replacement',
      () async {
    // DateTime.tryParse accepts overflowed dates/clocks on some inputs;
    // legacy year replacement must not delete those untrusted original rows.
    for (final timestamp in <String>[
      '2026-02-30T00:00:00.000Z',
      '2026-01-01T24:00:00.000Z',
      '2026-01-01T12:60:00.000Z',
      '2026-01-01T12:00:00+24:00',
    ]) {
      final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
      try {
        await _insertLegacyYear(db, 2028);
        await db.update(
          'taiwan_business_calendar_days',
          <String, Object?>{'updated_at': timestamp},
          where: 'calendar_date = ?',
          whereArgs: <Object?>['2028-07-03'],
        );
        final before = await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC');
        final status = await service.status(db, 2028);
        expect(status, isNotNull);
        expect(status!.isContiguous, isFalse,
            reason: 'Impossible timestamp cannot be trusted: $timestamp');
        final replacement = await _package(codec, year: 2028, sequence: 1);
        await expectLater(service.install(db, replacement),
            throwsA(isA<CalendarPackageConflictException>()));
        expect(await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC'), equals(before),
            reason: 'Failed promotion must retain every legacy row');
      } finally {
        await db.close();
      }
    }
  });

  test('B2.35 valid leap-day legacy timestamps permit safe upgrade', () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    addTearDown(db.close);
    await _insertLegacyYear(db, 2028);
    await db.update(
      'taiwan_business_calendar_days',
      <String, Object?>{'updated_at': '2024-02-29T23:59:59+08:00'},
      where: 'calendar_date = ?',
      whereArgs: <Object?>['2028-07-03'],
    );
    expect((await service.status(db, 2028))!.isContiguous, isTrue);
    final replacement = await _package(codec, year: 2028, sequence: 1);
    final result = await service.install(db, replacement);
    expect(result.disposition, CalendarPackageInstallDisposition.installed);
    expect((await service.status(db, 2028))!.hasCanonicalRowDigest, isTrue);
  });

  test('B2.29 rewritten canonical metadata cannot authorize verified LKG',
      () async {
    // A decoded-field digest does not authenticate unknown JSON keys or
    // noncanonical serialization. Only the original generated_at envelope
    // can remain a verified source for the same or a newer revision.
    for (final rewrite in <String Function(String)>[
      (canonical) {
        final fields = Map<String, Object?>.from(
          jsonDecode(canonical) as Map,
        );
        fields['untracked_authority'] = 'attacker-claim';
        return jsonEncode(fields);
      },
      (canonical) => ' $canonical',
    ]) {
      final db = await _openCalendarDatabase();
      try {
        final original = await _package(codec, year: 2028, sequence: 1);
        final newer = await _package(codec, year: 2028, sequence: 2);
        await service.install(db, original);
        final canonical = original.storedMetadata.encode();
        expect((await service.status(db, 2028))!.hasCanonicalRowDigest,
            isTrue);

        final rewritten = rewrite(canonical);
        expect(rewritten, isNot(canonical));
        await db.update(
          'taiwan_business_calendar_days',
          <String, Object?>{'source_revision': rewritten},
          where: 'source_year = ?',
          whereArgs: <Object?>[2028],
        );
        final before = await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC');
        final untrusted = await service.status(db, 2028);
        expect(untrusted, isNotNull);
        expect(untrusted!.hasCanonicalRowDigest, isFalse);
        expect(untrusted.isContiguous, isFalse);

        await expectLater(service.install(db, original),
            throwsA(isA<CalendarPackageConflictException>()));
        await expectLater(service.install(db, newer),
            throwsA(isA<CalendarPackageConflictException>()));
        expect(await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC'), equals(before),
            reason: 'Both idempotent and newer installs must retain '
                'rewritten metadata rows without destructive replacement');
      } finally {
        await db.close();
      }
    }
  });

  test('B2.29 untouched canonical metadata remains verified and idempotent',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    final status = await service.status(db, 2028);
    expect(status!.hasCanonicalRowDigest, isTrue);
    expect(status.digest, original.digest);
    final unchanged = await service.install(db, original);
    expect(unchanged.disposition, CalendarPackageInstallDisposition.unchanged);
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before));
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

  test('B2.19 AFTER INSERT same-count mutation rolls back verified LKG',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final replacement = await _package(
      codec, year: 2028, sequence: 2, closedDate: '2028-07-03',
    );
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    await db.execute('''
      CREATE TRIGGER corrupt_calendar_after_insert
      AFTER INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2028-07-03'
      BEGIN
        UPDATE taiwan_business_calendar_days
        SET is_business_day = 1, day_label = 'silent mutation'
        WHERE calendar_date = NEW.calendar_date;
      END
    ''');

    await expectLater(service.install(db, replacement),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before),
        reason: 'A successful SQLite batch is not post-write row proof.');
    final retained = await service.status(db, 2028);
    expect(retained!.digest, original.digest);
    expect(retained.hasCanonicalRowDigest, isTrue);
  });

  test('B2.19 AFTER INSERT silent row deletion rolls back verified LKG',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final replacement = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    await db.execute('''
      CREATE TRIGGER delete_calendar_after_insert
      AFTER INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2028-07-03'
      BEGIN
        DELETE FROM taiwan_business_calendar_days
        WHERE calendar_date = '2028-07-02';
      END
    ''');

    await expectLater(service.install(db, replacement),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before),
        reason: 'Missing post-insert rows must never replace the prior LKG.');
    expect((await service.status(db, 2028))!.digest, original.digest);
  });

  test('B2.20 AFTER INSERT timestamp rewrite rolls back verified LKG',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final replacement = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    await db.execute('''
      CREATE TRIGGER rewrite_calendar_timestamp_after_insert
      AFTER INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2028-07-03'
      BEGIN
        UPDATE taiwan_business_calendar_days
        SET updated_at = '1999-01-01T00:00:00.000Z'
        WHERE calendar_date = NEW.calendar_date;
      END
    ''');

    await expectLater(service.install(db, replacement),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before),
        reason: 'Silent timestamp tamper must not replace verified LKG.');
    final retained = await service.status(db, 2028);
    expect(retained!.digest, original.digest);
    expect(retained.hasCanonicalRowDigest, isTrue);
  });

  test('B2.22 later timestamp drift revokes canonical year authority', () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final newer = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original,
        importedAt: DateTime.utc(2027, 7, 1));
    final verified = await service.status(db, 2028);
    expect(verified!.hasCanonicalRowDigest, isTrue);
    expect(verified.digest, original.digest);

    // A later SQLite edit is not part of install() and must not retain LKG.
    await db.update('taiwan_business_calendar_days',
        <String, Object?>{'updated_at': '2001-01-01T00:00:00.000Z'},
        where: 'calendar_date = ?',
        whereArgs: <Object?>['2028-07-03']);
    final corrupted = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    final status = await service.status(db, 2028);
    expect(status!.isContiguous, isFalse);
    expect(status.hasCanonicalRowDigest, isFalse);
    expect(status.sequence, 0);
    expect(status.digest, isEmpty);
    expect(
        await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
        CalendarAnnualUpdateDecision.currentYearNotVerified);
    await expectLater(service.install(db, newer),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(corrupted),
        reason: 'Untrusted stored year must not be overwritten or repaired');
  });

  test('B2.22 malformed first-row timestamp fails closed without writes',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    await db.update('taiwan_business_calendar_days',
        <String, Object?>{'updated_at': 'not-an-iso-utc-timestamp'},
        where: 'calendar_date = ?',
        whereArgs: <Object?>['2028-01-01']);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    final status = await service.status(db, 2028);
    expect(status!.importedAt, 'not-an-iso-utc-timestamp');
    expect(status.isContiguous, isFalse);
    expect(status.hasCanonicalRowDigest, isFalse);
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before));
  });

  test('B2.36 uniform noncanonical installed timestamps revoke verified LKG',
      () async {
    // Even if every persisted row is rewritten identically, the imported
    // timestamp must remain the canonical UTC form emitted by install().
    for (final timestamp in <String>[
      '2026-02-30T00:00:00.000Z',
      '2026-01-01T24:00:00.000Z',
      '2026-01-01T12:60:00.000Z',
      '2026-01-01T00:00:00Z',
    ]) {
      final db = await _openCalendarDatabase();
      try {
        final original = await _package(codec, year: 2028, sequence: 1);
        final newer = await _package(codec, year: 2028, sequence: 2);
        await service.install(db, original,
            importedAt: DateTime.utc(2027, 7, 1));
        expect((await service.status(db, 2028))!.hasCanonicalRowDigest, isTrue);

        await db.update(
          'taiwan_business_calendar_days',
          <String, Object?>{'updated_at': timestamp},
          where: 'source_year = ?',
          whereArgs: <Object?>[2028],
        );
        final before = await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC');
        expect(before, hasLength(366));
        final status = await service.status(db, 2028);
        expect(status, isNotNull);
        expect(status!.hasCanonicalRowDigest, isFalse,
            reason: 'Uniform timestamp rewrite must revoke LKG: $timestamp');
        expect(status.isContiguous, isFalse);
        expect(status.sequence, 0);
        expect(status.digest, isEmpty);
        expect(
          await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
          CalendarAnnualUpdateDecision.currentYearNotVerified,
        );
        await expectLater(service.install(db, newer),
            throwsA(isA<CalendarPackageConflictException>()));
        expect(await db.query('taiwan_business_calendar_days',
            orderBy: 'calendar_date ASC'), equals(before),
            reason: 'Failed promotion must retain all original rows');
      } finally {
        await db.close();
      }
    }
  });

  test('B2.36 canonical leap-day UTC provenance retains install authority',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final newer = await _package(codec, year: 2028, sequence: 2);
    final leapDay = DateTime.utc(2024, 2, 29, 23, 59, 59);
    await service.install(db, original, importedAt: leapDay);
    final status = await service.status(db, 2028);
    expect(status, isNotNull);
    expect(status!.hasCanonicalRowDigest, isTrue);
    expect(status.importedAt, leapDay.toIso8601String());
    expect((await service.install(db, original)).disposition,
        CalendarPackageInstallDisposition.unchanged);
    expect((await service.install(db, newer)).disposition,
        CalendarPackageInstallDisposition.installed);
    expect((await service.status(db, 2028))!.hasCanonicalRowDigest, isTrue);
  });

  test('B2.23 NULL legacy primary-key date fails closed without writes',
      () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    addTearDown(db.close);
    await _insertLegacyDay(db, year: 2028, date: '2028-01-01');
    // SQLite rowid tables permit NULL in a TEXT PRIMARY KEY without NOT NULL.
    await db.rawUpdate('''
      UPDATE taiwan_business_calendar_days SET calendar_date = NULL
      WHERE source_year = 2028
    ''');
    final before = await db.query('taiwan_business_calendar_days');
    expect(before.single['calendar_date'], isNull);
    expect(await service.status(db, 2028), isNull);
    expect(
        await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
        CalendarAnnualUpdateDecision.currentYearNotVerified);
    final replacement = await _package(codec, year: 2028, sequence: 1);
    await expectLater(service.install(db, replacement),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await db.query('taiwan_business_calendar_days'), equals(before));
  });

  test('B2.23 BLOB timestamp revokes verified year without writes', () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final replacement = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    expect((await service.status(db, 2028))!.hasCanonicalRowDigest, isTrue);
    // SQLite TEXT affinity does not prevent a later BLOB value.
    await db.rawUpdate('''
      UPDATE taiwan_business_calendar_days SET updated_at = x'0102'
      WHERE calendar_date = '2028-01-01'
    ''');
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    expect(before.first['updated_at'], isNot(isA<String>()));
    expect(await service.status(db, 2028), isNull);
    expect(
        await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
        CalendarAnnualUpdateDecision.currentYearNotVerified);
    await expectLater(service.install(db, replacement),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before));
  });

  test('B2.21 legacy TEXT flag trigger fails typed and retains LKG', () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    final replacement = await _package(codec, year: 2028, sequence: 2);
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    final beforeStatus = await service.status(db, 2028);
    expect(beforeStatus!.hasCanonicalRowDigest, isTrue);
    await db.execute("""
      CREATE TRIGGER calendar_text_flag_after_insert
      AFTER INSERT ON taiwan_business_calendar_days
      WHEN NEW.calendar_date = '2028-07-03'
      BEGIN
        UPDATE taiwan_business_calendar_days
        SET is_business_day = 'corrupted-text'
        WHERE calendar_date = NEW.calendar_date;
      END
    """);
    await expectLater(service.install(db, replacement),
        throwsA(isA<CalendarPackageConflictException>()));
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before),
        reason: 'TEXT flag must rollback entire replacement transaction');
    final retained = await service.status(db, 2028);
    expect(retained!.digest, original.digest);
    expect(retained.hasCanonicalRowDigest, isTrue);
  });

  test('B2.21 integer flags remain idempotent on legacy SQLite', () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    final unchanged = await service.install(db, original);
    expect(unchanged.disposition, CalendarPackageInstallDisposition.unchanged);
    expect((await service.status(db, 2028))!.digest, original.digest);
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

  test('B2.24 second December read rejects malformed rows after first workday',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    expect((await service.status(db, 2028))!.hasCanonicalRowDigest, isTrue);

    // status() sees the real, verified full year. The later December query
    // alone receives an adversarial same-count view; this models a changed
    // second read without touching Owner data or altering the SQLite LKG.
    for (final corruption in <Map<String, Object?>>[
      <String, Object?>{'calendar_date': '2028-12-15'},
      <String, Object?>{'is_business_day': '1'},
      <String, Object?>{'is_business_day': 2},
      <String, Object?>{'is_business_day': null},
    ]) {
      final view = _CalendarDecemberTamperingExecutor(db, corruption);
      expect(
        await service.annualUpdateDecision(view, DateTime.utc(2028, 12, 5)),
        CalendarAnnualUpdateDecision.currentYearNotVerified,
        reason: 'A later malformed December row must fail closed: $corruption',
      );
    }
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.checkOfficialSource,
      reason: 'An intact verified year keeps normal update eligibility',
    );
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before));
    expect((await service.status(db, 2028))!.digest, original.digest);
  });

  test('B2.27 second December SQLite read error fails closed without writes',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    final injected = _CalendarReadFailureExecutor(db, failDecember: true);
    expect(
      await service.annualUpdateDecision(injected, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.currentYearNotVerified,
      reason: 'A second-read SQLite exception must not escape or authorize',
    );
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before));
    expect((await service.status(db, 2028))!.digest, original.digest);
    expect(await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
        CalendarAnnualUpdateDecision.checkOfficialSource);
  });

  test('B2.27 unreadable next-year existence query fails closed without writes',
      () async {
    final db = await _openCalendarDatabase();
    addTearDown(db.close);
    final original = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, original);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    final injected = _CalendarReadFailureExecutor(db, failNextYear: true);
    expect(
      await service.annualUpdateDecision(injected, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.nextYearUntrusted,
      reason: 'Failed existence read must not imply absent next year',
    );
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before));
    expect((await service.status(db, 2028))!.digest, original.digest);
    expect(await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
        CalendarAnnualUpdateDecision.checkOfficialSource);
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

  test('B2.26 missing calendar table is unverified without writes', () async {
    // An older on-device database may not yet have the optional B2 table.
    // Only a real calendar package install requires that table to exist.
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE legacy_guard (value TEXT NOT NULL)');
    await db.insert('legacy_guard', <String, Object?>{'value': 'LKG'});
    final before = await db.query('legacy_guard');

    expect(await service.status(db, 2028), isNull);
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.currentYearNotVerified,
    );
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 11, 5)),
      CalendarAnnualUpdateDecision.outsideDecember,
    );
    final incoming = await _package(codec, year: 2028, sequence: 1);
    await expectLater(
      service.install(db, incoming),
      throwsA(isA<DatabaseException>()),
      reason: 'Missing table must not become a silently successful install',
    );
    expect(await db.query('legacy_guard'), equals(before),
        reason: 'No migration, install or calendar read may alter old LKG');
  });

  test('B2.25 unreadable next-year rows never look like absent year',
      () async {
    // Each isolated SQLite FFI case has a real verified current-year LKG.
    // Legacy rowid tables permit NULL TEXT PRIMARY KEY and BLOB TEXT values.
    // status(nextYear)==null must not turn a damaged year into an absent one.
    final corruptions = <String>[
      'UPDATE taiwan_business_calendar_days '
          'SET calendar_date = NULL WHERE source_year = 2029',
      '''UPDATE taiwan_business_calendar_days
          SET updated_at = x'0102' WHERE source_year = 2029''',
      '''UPDATE taiwan_business_calendar_days
          SET source_revision = x'0102' WHERE source_year = 2029''',
      '''UPDATE taiwan_business_calendar_days
          SET source_url = x'0102' WHERE source_year = 2029''',
    ];
    for (final corruption in corruptions) {
      final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
      // sqflite_ffi reuses the same in-memory database until it is closed.
      // Close each fixture before opening the next corruption case.
      try {
        final current = await _package(codec, year: 2028, sequence: 1);
        await service.install(db, current);
        expect((await service.status(db, 2028))!.hasCanonicalRowDigest, isTrue);
        await _insertLegacyDay(db, year: 2029, date: '2029-01-01');
        await db.execute(corruption);
        expect(await service.status(db, 2029), isNull,
            reason: 'Malformed next-year storage class must be untrusted');
        final before = await db.query('taiwan_business_calendar_days',
            orderBy: 'source_year ASC, calendar_date ASC');
        expect(
          await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
          CalendarAnnualUpdateDecision.nextYearUntrusted,
          reason: 'Unparseable next-year rows cannot authorize a source check',
        );
        expect(
          await db.query('taiwan_business_calendar_days',
              orderBy: 'source_year ASC, calendar_date ASC'),
          equals(before),
          reason: 'Read-only eligibility must preserve both years byte-for-byte',
        );
        expect((await service.status(db, 2028))!.digest, current.digest);
      } finally {
        await db.close();
      }
    }
  });

  test('B2.25 truly absent next year retains source-check eligibility',
      () async {
    final db = await _openLegacyCalendarDatabaseWithoutModernConstraints();
    addTearDown(db.close);
    final current = await _package(codec, year: 2028, sequence: 1);
    await service.install(db, current);
    final before = await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC');
    expect(await service.status(db, 2029), isNull);
    expect(
      await service.annualUpdateDecision(db, DateTime.utc(2028, 12, 5)),
      CalendarAnnualUpdateDecision.checkOfficialSource,
    );
    expect(await db.query('taiwan_business_calendar_days',
        orderBy: 'calendar_date ASC'), equals(before));
    expect((await service.status(db, 2028))!.digest, current.digest);
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

// B2.27: a real isolated SQLite FFI read error is injected only at the
// second December query or next-year existence read; the first verified
// current-year read and the stored LKG remain untouched.
class _CalendarReadFailureExecutor extends _CalendarDecemberTamperingExecutor {
  _CalendarReadFailureExecutor(Database db, {
    this.failDecember = false,
    this.failNextYear = false,
  }) : super(db, const <String, Object?>{});

  final bool failDecember;
  final bool failNextYear;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    if ((failDecember &&
            where ==
                'source_year = ? AND calendar_date >= ? AND calendar_date <= ?') ||
        (failNextYear &&
            where == 'source_year = ?' &&
            whereArgs != null &&
            whereArgs.length == 1 &&
            whereArgs.single == 2029)) {
      // Real SQLite FFI DatabaseException, not a fabricated exception type.
      return db.rawQuery('SELECT * FROM b2_27_missing_read_table');
    }
    return super.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }
}

 // B2.24 test-only executor: preserve the real verified first query and
 // tamper only the later December read. No database writes or Owner data.
class _CalendarDecemberTamperingExecutor implements DatabaseExecutor {
  _CalendarDecemberTamperingExecutor(this.db, this.corruption);

  final Database db;
  final Map<String, Object?> corruption;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final rows = await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    if (where !=
        'source_year = ? AND calendar_date >= ? AND calendar_date <= ?') {
      return rows;
    }
    final altered = rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    altered[15].addAll(corruption);
    return altered;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
