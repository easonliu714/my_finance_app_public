import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v22.dart';

class MerchantLegalNameObservation {
  const MerchantLegalNameObservation({
    required this.id,
    required this.sellerIdentifier,
    required this.legalName,
    required this.sourceReference,
    required this.observedAt,
  });

  final String id;
  final String sellerIdentifier;
  final String legalName;
  final String sourceReference;
  final DateTime observedAt;
}

/// P4.20.5 read model for legal-name history.
///
/// Official registry refreshes may update the current LegalEntity projection,
/// but historical legal names remain user-inspectable through append-only
/// identity observations. This service never grants sellerTaxId authority,
/// never binds a MerchantBrand, and never writes a formal transaction.
class MerchantLegalNameHistoryService {
  const MerchantLegalNameHistoryService({this.database});

  final DatabaseExecutor? database;

  Future<DatabaseExecutor> get _db async {
    final resolved =
        database ?? await ProductionDatabaseCoordinator.instance.database;
    await createCanonicalProductionV22Tables(resolved);
    return resolved;
  }

  Future<List<MerchantLegalNameObservation>> listForSellerIdentifier(
    String sellerIdentifier,
  ) async {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(seller)) {
      return const <MerchantLegalNameObservation>[];
    }

    final db = await _db;
    final rows = await db.query(
      'merchant_identity_observations',
      columns: <String>[
        'id',
        'seller_identifier',
        'literal_name',
        'source_reference',
        'observed_at',
      ],
      where: "seller_identifier = ? AND source = 'official_registry'",
      whereArgs: <Object?>[seller],
      orderBy: 'observed_at ASC, created_at ASC, id ASC',
    );

    return rows.map((row) {
      return MerchantLegalNameObservation(
        id: row['id']?.toString() ?? '',
        sellerIdentifier: row['seller_identifier']?.toString() ?? '',
        legalName: row['literal_name']?.toString() ?? '',
        sourceReference: row['source_reference']?.toString() ?? '',
        observedAt: DateTime.parse(row['observed_at']?.toString() ?? ''),
      );
    }).toList(growable: false);
  }
}