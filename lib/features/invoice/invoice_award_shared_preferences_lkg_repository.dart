import 'package:shared_preferences/shared_preferences.dart';

import 'invoice_award_lkg_repository.dart';

/// Small, durable Last-Known-Good store for validated general-award snapshots.
///
/// This adapter intentionally stores only the bounded JSON snapshot emitted by
/// [OfficialInvoiceAwardLkgCodec]. It performs no SQLite migration and is not
/// suitable for large cloud-exclusive award lists.
class SharedPreferencesOfficialInvoiceAwardLkgRepository
    implements OfficialInvoiceAwardLkgRepository {
  SharedPreferencesOfficialInvoiceAwardLkgRepository(
    this._preferences, {
    this.keyPrefix = 'invoice_award.general_lkg.v1.',
  });

  final SharedPreferences _preferences;
  final String keyPrefix;

  @override
  Future<OfficialInvoiceAwardLkgSnapshot?> read(String periodId) async {
    final normalizedPeriodId = _normalizePeriodId(periodId);
    final payload = _preferences.getString('$keyPrefix$normalizedPeriodId');
    if (payload == null || payload.isEmpty) return null;
    return OfficialInvoiceAwardLkgSnapshot(
      periodId: normalizedPeriodId,
      payload: payload,
    );
  }

  @override
  Future<void> replaceValidated(OfficialInvoiceAwardLkgSnapshot snapshot) async {
    final normalizedPeriodId = _normalizePeriodId(snapshot.periodId);
    if (snapshot.payload.isEmpty) {
      throw const FormatException('Refusing to persist an empty award snapshot');
    }

    final stored = await _preferences.setString(
      '$keyPrefix$normalizedPeriodId',
      snapshot.payload,
    );
    if (!stored) {
      throw StateError('Failed to persist validated award snapshot');
    }
  }

  String _normalizePeriodId(String periodId) {
    final normalized = periodId.trim();
    if (!RegExp(r'^\d{3}-(?:01-02|03-04|05-06|07-08|09-10|11-12)$')
        .hasMatch(normalized)) {
      throw FormatException('Invalid award period id: $periodId');
    }
    return normalized;
  }
}
