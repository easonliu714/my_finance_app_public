import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';

void main() {
  const codec = TaiwanBusinessCalendarPackageCodec();

  test('builds and verifies a deterministic leap-year package', () async {
    final package = await codec.build(
      sourceYear: 2028,
      sourceRevision: 'DGPA-117-test',
      revisionSequence: 1,
      sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
      sourcePublishedAt: '2027-06-30',
      generatedAt: '2027-07-01T00:00:00.000Z',
      days: _daysForYear(2028),
    );

    expect(package.days, hasLength(366));
    expect(package.coverageStart, '2028-01-01');
    expect(package.coverageEnd, '2028-12-31');
    expect(package.digest, hasLength(64));

    final decoded = await codec.decodeAndValidate(package.encode());
    expect(decoded.digest, package.digest);
    expect(decoded.toJson(), package.toJson());
  });

  test('Dart digest matches the build-tool canonical contract', () async {
    final package = await codec.build(
      sourceYear: 2028,
      sourceRevision: 'DGPA-117-test',
      revisionSequence: 1,
      sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
      sourcePublishedAt: '2027-06-30',
      generatedAt: '2027-07-01T00:00:00.000Z',
      days: _daysForYear(2028, weekendLabel: ''),
    );

    expect(
      package.digest,
      'c58459d035e8e095fd9f6e90343e72192404f675f7ad6fd74282f0bc3f10b7dd',
    );
  });

  test('same normalized input produces the same digest', () async {
    Future<TaiwanBusinessCalendarYearPackage> build() => codec.build(
          sourceYear: 2029,
          sourceRevision: 'DGPA-118-test',
          revisionSequence: 3,
          sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
          sourcePublishedAt: '2028-06-30',
          generatedAt: '2028-07-01T00:00:00.000Z',
          days: _daysForYear(2029),
        );

    expect((await build()).digest, (await build()).digest);
  });

  test('rejects incomplete and non-contiguous years', () async {
    final incomplete = _daysForYear(2028)..removeLast();
    await expectLater(
      codec.build(
        sourceYear: 2028,
        sourceRevision: 'DGPA-117-test',
        revisionSequence: 1,
        sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
        sourcePublishedAt: '2027-06-30',
        generatedAt: '2027-07-01T00:00:00.000Z',
        days: incomplete,
      ),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );

    final nonContiguous = _daysForYear(2028);
    nonContiguous[10] = TaiwanBusinessCalendarPackageDay(
      dateKey: nonContiguous[11].dateKey,
      isBusinessDay: true,
      label: '',
    );
    await expectLater(
      codec.build(
        sourceYear: 2028,
        sourceRevision: 'DGPA-117-test',
        revisionSequence: 1,
        sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
        sourcePublishedAt: '2027-06-30',
        generatedAt: '2027-07-01T00:00:00.000Z',
        days: nonContiguous,
      ),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
  });

  test('rejects invalid flags and digest tampering', () async {
    final package = await codec.build(
      sourceYear: 2028,
      sourceRevision: 'DGPA-117-test',
      revisionSequence: 1,
      sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
      sourcePublishedAt: '2027-06-30',
      generatedAt: '2027-07-01T00:00:00.000Z',
      days: _daysForYear(2028),
    );
    final invalidFlag = Map<String, Object?>.from(
      jsonDecode(package.encode()) as Map,
    );
    final invalidFlagDays = invalidFlag['days']! as List<Object?>;
    final first = Map<String, Object?>.from(invalidFlagDays.first! as Map);
    first['is_business_day'] = 1;
    invalidFlagDays[0] = first;
    await expectLater(
      codec.decodeAndValidate(jsonEncode(invalidFlag)),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );

    final tampered = Map<String, Object?>.from(
      jsonDecode(package.encode()) as Map,
    );
    final tamperedDays = tampered['days']! as List<Object?>;
    final second = Map<String, Object?>.from(tamperedDays[1]! as Map);
    second['label'] = 'tampered';
    tamperedDays[1] = second;
    await expectLater(
      codec.decodeAndValidate(jsonEncode(tampered)),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
  });

  test('stored metadata round-trips and legacy text stays detectable', () async {
    final package = await codec.build(
      sourceYear: 2028,
      sourceRevision: 'DGPA-117-test',
      revisionSequence: 2,
      sourceUrl: 'https://www.dgpa.gov.tw/informationlist?uid=41',
      sourcePublishedAt: '2027-07-15',
      generatedAt: '2027-07-16T00:00:00.000Z',
      days: _daysForYear(2028),
    );

    final metadata = TaiwanBusinessCalendarStoredMetadata.tryDecode(
      package.storedMetadata.encode(),
    );
    expect(metadata, isNotNull);
    expect(metadata!.sourceRevision, 'DGPA-117-test');
    expect(metadata.revisionSequence, 2);
    expect(metadata.rowCount, 366);
    expect(
      TaiwanBusinessCalendarStoredMetadata.tryDecode('DGPA-legacy'),
      isNull,
    );
  });
}

List<TaiwanBusinessCalendarPackageDay> _daysForYear(
  int year, {
  String weekendLabel = 'weekend',
}) {
  final days = <TaiwanBusinessCalendarPackageDay>[];
  var cursor = DateTime.utc(year, 1, 1);
  final end = DateTime.utc(year + 1, 1, 1);
  while (cursor.isBefore(end)) {
    final weekend = cursor.weekday == DateTime.saturday ||
        cursor.weekday == DateTime.sunday;
    days.add(
      TaiwanBusinessCalendarPackageDay(
        dateKey: _dateKey(cursor),
        isBusinessDay: !weekend,
        label: weekend ? weekendLabel : '',
      ),
    );
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

String _dateKey(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)}';
}
