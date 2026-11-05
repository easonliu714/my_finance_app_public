import 'dart:async';
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
  test('B2.14e bounded official stream preserves bytes and order', () async {
    final result =
        await TaiwanBusinessCalendarAnnualSourceCheck.readBoundedOfficialCsvStream(
      Stream<List<int>>.fromIterable(<List<int>>[
        <int>[0xef, 0xbb],
        <int>[0xbf, 0x31, 0x32],
      ]),
      maxElapsed: const Duration(seconds: 1),
    );
    expect(result, orderedEquals(<int>[0xef, 0xbb, 0xbf, 0x31, 0x32]));
  });

  test('B2.14e stalled stream hits total deadline and cancels', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () { cancelled = true; },
    );
    final watch = Stopwatch()..start();
    await expectLater(
      TaiwanBusinessCalendarAnnualSourceCheck.readBoundedOfficialCsvStream(
        source.stream,
        maxElapsed: const Duration(milliseconds: 25),
      ),
      throwsA(isA<TimeoutException>()),
    );
    watch.stop();
    expect(cancelled, isTrue, reason: 'Timeout must release HTTP stream');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    await source.close();
  });

  test('B2.14e oversized stream cancels before unbounded buffering', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () { cancelled = true; },
    );
    final result =
        TaiwanBusinessCalendarAnnualSourceCheck.readBoundedOfficialCsvStream(
      source.stream,
      maxElapsed: const Duration(seconds: 1),
    );
    source.add(List<int>.filled(256 * 1024 + 1, 0));
    await expectLater(result, throwsA(isA<FormatException>()));
    expect(cancelled, isTrue);
    await source.close();
  });

}
