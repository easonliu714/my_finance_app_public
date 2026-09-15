import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v22.dart';

class MerchantBranchOutletHistoryEntry {
  const MerchantBranchOutletHistoryEntry({
    required this.outletId,
    required this.legalEntityId,
    required this.sellerIdentifier,
    required this.outletLabel,
    required this.officialBranchIdentifier,
    required this.address,
    required this.source,
    required this.sourceReference,
    required this.observedAt,
    this.validFrom,
    this.validTo,
  });

  final String outletId;
  final String legalEntityId;
  final String sellerIdentifier;
  final String outletLabel;
  final String officialBranchIdentifier;
  final String address;
  final String source;
  final String sourceReference;
  final DateTime observedAt;
  final DateTime? validFrom;
  final DateTime? validTo;

  bool get isCurrent => validTo == null;
}

/// Read-only P4.20.5 projection for user-owned branch/outlet lineage.
///
/// The source of truth remains append-only merchant identity observations plus
/// effective-dated outlet rows. This service never infers authority from OCR,
/// AI, or a Registry hit and performs no formal accounting write.
class MerchantBranchOutletHistoryService {
  const MerchantBranchOutletHistoryService({this.database});

  final DatabaseExecutor? database;

  Future<DatabaseExecutor> get _db async {
    final resolved =
        database ?? await ProductionDatabaseCoordinator.instance.database;
    await createCanonicalProductionV22Tables(resolved);
    return resolved;
  }

  Future<List<MerchantBranchOutletHistoryEntry>> listForSellerIdentifier(
    String sellerIdentifier,
  ) async {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(seller)) {
      return const <MerchantBranchOutletHistoryEntry>[];
    }
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        o.id AS outlet_id,
        o.legal_entity_id,
        le.seller_identifier,
        o.outlet_label,
        o.official_branch_identifier,
        o.address,
        o.valid_from,
        o.valid_to,
        obs.source,
        obs.source_reference,
        obs.observed_at
      FROM merchant_branches_or_outlets o
      JOIN merchant_legal_entities le ON le.id = o.legal_entity_id
      JOIN merchant_identity_observations obs ON obs.branch_or_outlet_id = o.id
      WHERE le.jurisdiction = 'TW'
        AND le.seller_identifier = ?
      ORDER BY obs.observed_at ASC, obs.created_at ASC, obs.id ASC
    ''', <Object?>[seller]);
    return rows.map((row) {
      DateTime? parseNullable(Object? value) {
        final raw = value?.toString().trim() ?? '';
        return raw.isEmpty ? null : DateTime.parse(raw);
      }

      return MerchantBranchOutletHistoryEntry(
        outletId: row['outlet_id']?.toString() ?? '',
        legalEntityId: row['legal_entity_id']?.toString() ?? '',
        sellerIdentifier: row['seller_identifier']?.toString() ?? '',
        outletLabel: row['outlet_label']?.toString() ?? '',
        officialBranchIdentifier:
            row['official_branch_identifier']?.toString() ?? '',
        address: row['address']?.toString() ?? '',
        source: row['source']?.toString() ?? '',
        sourceReference: row['source_reference']?.toString() ?? '',
        observedAt: DateTime.parse(row['observed_at']?.toString() ?? ''),
        validFrom: parseNullable(row['valid_from']),
        validTo: parseNullable(row['valid_to']),
      );
    }).toList(growable: false);
  }
}