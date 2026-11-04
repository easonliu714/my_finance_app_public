import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'taiwan_business_calendar_official_116_stage.dart';

/// B2.14c: advisory local-only manual source-check receipt. NEVER a calendar
/// revision, installation proof, backup authority or accounting record.
class TaiwanBusinessCalendarAnnualCheckReceiptStore {
  const TaiwanBusinessCalendarAnnualCheckReceiptStore({
    this.readRaw, this.writeRaw,
  });
  static const key = 'b2.official116.manual-check.v1';
  final Future<String?> Function()? readRaw;
  final Future<void> Function(String)? writeRaw;

  static String _day(DateTime d) => d.toUtc()
      .add(const Duration(hours: 8)).toIso8601String().substring(0, 10);
  static bool _digest(String d) => RegExp(r'^[0-9a-f]{64}$').hasMatch(d);

  Future<String?> _read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  Future<void> _write(String raw) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, raw)) {
      throw StateError('Receipt persistence failed.');
    }
  }

  Future<DateTime?> readVerified({
    required int year, required String digest, required DateTime now,
  }) async {
    if (year != 2026 || !_digest(digest)) return null;
    final raw = await (readRaw?.call() ?? _read());
    if (raw == null || raw.length > 512) return null;
    try {
      final v = jsonDecode(raw);
      if (v is! Map<String, dynamic> || v.length != 5 ||
          v['year'] != year || v['digest'] != digest ||
          v['target_year'] != 2027 ||
          v['target_sha256'] !=
              TaiwanBusinessCalendarOfficial116Stage.pinnedSha256 ||
          v['checked_at'] is! String ||
          !(v['checked_at'] as String).endsWith('Z')) return null;
      final checked = DateTime.tryParse(v['checked_at'] as String);
      if (checked == null || checked.isAfter(now.toUtc()) ||
          _day(checked) != _day(now)) return null;
      return checked.toUtc();
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> writeVerified({
    required int year, required String digest, required DateTime checkedAt,
  }) async {
    if (year != 2026 || !_digest(digest)) {
      throw const FormatException('Untrusted calendar receipt context.');
    }
    final raw = jsonEncode(<String, Object>{
      'year': year, 'digest': digest, 'target_year': 2027,
      'target_sha256': TaiwanBusinessCalendarOfficial116Stage.pinnedSha256,
      'checked_at': checkedAt.toUtc().toIso8601String(),
    });
    await (writeRaw?.call(raw) ?? _write(raw));
  }
}
