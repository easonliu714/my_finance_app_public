import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_csv_import.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_official_116_stage.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';

void main() {
  const codec = TaiwanBusinessCalendarOfficialCsvCodec();
  const stage = TaiwanBusinessCalendarOfficial116Stage();

  test('B2.9 parse-only full-year synthetic positive and immutable days', () {
    final days = codec.parseFullYear(_synthetic2027(), sourceYear: 2027);
    expect(days, hasLength(365));
    expect(days.first.dateKey, '2027-01-01');
    expect(days.last.dateKey, '2027-12-31');
    expect(() => days.clear(), throwsUnsupportedError);
  });

  test('B2.9 wrong-year and altered weekday reject before package build', () {
    final bytes = _synthetic2027();
    expect(
      () => codec.parseFullYear(bytes, sourceYear: 2028),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
    final text = utf8.decode(bytes).replaceFirst('20270101,五', '20270101,六');
    expect(
      () => codec.parseFullYear(Uint8List.fromList(utf8.encode(text)),
          sourceYear: 2027),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
  });

  test('B2.9 exact-size forged CSV, empty and oversize fail closed', () async {
    for (final bytes in <Uint8List>[
      Uint8List(0),
      Uint8List(TaiwanBusinessCalendarOfficial116Stage.pinnedByteLength),
      _synthetic2027(),
      Uint8List(TaiwanBusinessCalendarOfficialCsvCodec.maxCsvBytes + 1),
    ]) {
      await expectLater(stage.verify(bytes),
          throwsA(isA<TaiwanBusinessCalendarPackageException>()));
    }
  });
}

Uint8List _synthetic2027() {
  final output = StringBuffer('\uFEFF西元日期,星期,是否放假,備註\r\n');
  const weekdays = <String>['日', '一', '二', '三', '四', '五', '六'];
  var day = DateTime.utc(2027, 1, 1);
  final end = DateTime.utc(2028, 1, 1);
  while (day.isBefore(end)) {
    final date = day.toIso8601String().substring(0, 10).replaceAll('-', '');
    output.write(date);
    output.write(',');
    output.write(weekdays[day.weekday % 7]);
    output.write(',0,\r\n');
    day = day.add(const Duration(days: 1));
  }
  return Uint8List.fromList(utf8.encode(output.toString()));
}
