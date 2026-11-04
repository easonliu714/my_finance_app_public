import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_annual_source_check.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_package.dart';

void main() {
  test('B2.14b construction cannot trigger a network request', () async {
    var calls = 0;
    final checker = TaiwanBusinessCalendarAnnualSourceCheck(
      readPinnedCsv: () async {
        calls++;
        return Uint8List(6511);
      },
    );
    expect(calls, 0);
    await expectLater(
      checker.check(),
      throwsA(isA<TaiwanBusinessCalendarPackageException>()),
    );
    expect(calls, 1);
  });

  test('B2.14b oversized or corrupted bytes never yield a receipt',
      () async {
    for (final bytes in <Uint8List>[
      Uint8List(256 * 1024 + 1),
      Uint8List.fromList(<int>[0xef, 0xbb, 0xbf]),
    ]) {
      await expectLater(
        TaiwanBusinessCalendarAnnualSourceCheck(
          readPinnedCsv: () async => bytes,
        ).check(),
        throwsA(isA<TaiwanBusinessCalendarPackageException>()),
      );
    }
  });
}
