import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar_annual_check_receipt.dart';

void main() {
  final digest = List<String>.filled(64, 'a').join();
  final now = DateTime.utc(2026, 11, 30, 16, 1);

  test('B2.14c verified same-Taipei-day receipt, changed day/year/digest rejected', () async {
    String? raw;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw, writeRaw: (v) async { raw = v; });
    await store.writeVerified(year: 2026, digest: digest, checkedAt: now);
    expect(await store.readVerified(year: 2026, digest: digest, now: now), now);
    expect(await store.readVerified(year: 2026, digest: digest,
      now: now.add(const Duration(days: 1))), isNull);
    expect(await store.readVerified(year: 2027, digest: digest, now: now), isNull);
    expect(await store.readVerified(year: 2026,
      digest: List<String>.filled(64, 'b').join(), now: now), isNull);
  });

  test('B2.14c tampered source pin, future timestamp and corrupt JSON fail open', () async {
    String? raw;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      readRaw: () async => raw, writeRaw: (v) async { raw = v; });
    await store.writeVerified(year: 2026, digest: digest, checkedAt: now);
    final valid = raw!;
    final tampered = jsonDecode(valid) as Map<String, dynamic>;
    tampered['target_sha256'] = List<String>.filled(64, 'f').join();
    raw = jsonEncode(tampered);
    expect(await store.readVerified(year: 2026, digest: digest, now: now), isNull);
    tampered['target_sha256'] = (jsonDecode(valid) as Map<String, dynamic>)['target_sha256'];
    tampered['checked_at'] = now.add(const Duration(minutes: 1)).toIso8601String();
    raw = jsonEncode(tampered);
    expect(await store.readVerified(year: 2026, digest: digest, now: now), isNull);
    raw = '{corrupt';
    expect(await store.readVerified(year: 2026, digest: digest, now: now), isNull);
  });

  test('B2.14c invalid year or digest never writes', () async {
    var writes = 0;
    final store = TaiwanBusinessCalendarAnnualCheckReceiptStore(
      writeRaw: (_) async { writes++; });
    await expectLater(store.writeVerified(year: 2027, digest: digest,
      checkedAt: now), throwsFormatException);
    await expectLater(store.writeVerified(year: 2026, digest: 'bad',
      checkedAt: now), throwsFormatException);
    expect(writes, 0);
  });
}
