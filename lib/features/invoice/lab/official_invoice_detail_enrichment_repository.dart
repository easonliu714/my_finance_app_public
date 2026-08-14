import 'package:sqflite/sqflite.dart';

import '../../../database/production_database_coordinator.dart';
import '../../../database/production_schema_v15.dart';
import 'canonical_cloud_invoice_persistence_codec.dart';
import 'official_invoice_detail_enrichment.dart';

class OfficialInvoiceDetailEnrichmentRepository {
  OfficialInvoiceDetailEnrichmentRepository({
    Future<Database> Function()? databaseProvider,
    DateTime Function()? clock,
  })  : _databaseProvider = databaseProvider ??
            (() => ProductionDatabaseCoordinator.instance.database),
        _clock = clock ?? DateTime.now;

  final Future<Database> Function() _databaseProvider;
  final DateTime Function() _clock;

  Future<int> saveValidated(
    Iterable<OfficialInvoiceDetailEnrichment> enrichments,
  ) async {
    final accepted = enrichments
        .where(
          (item) =>
              item.success &&
              item.invoiceIdentityMatches &&
              item.detailTotalInternallyConsistent &&
              item.detailTotalMatchesCsv &&
              item.exactTimestamp != null &&
              item.currencyCode != null &&
              item.expectedTotal != null &&
              item.detailTotal != null,
        )
        .toList(growable: false);
    if (accepted.isEmpty) return 0;

    final db = await _databaseProvider();
    await createCanonicalProductionV15Tables(db);
    final now = _clock().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      for (final item in accepted) {
        await transaction.insert(
          'cloud_invoice_detail_enrichments',
          <String, Object?>{
            'invoice_number': item.invoiceNumber,
            'selector_profile_version': item.selectorProfileVersion,
            'fetched_at': item.fetchedAt.toUtc().toIso8601String(),
            'exact_timestamp': item.exactTimestamp!.toIso8601String(),
            'currency_code': item.currencyCode!.trim().toUpperCase(),
            'official_status': item.officialStatus,
            'seller_identifier': item.sellerIdentifier,
            'seller_name': item.sellerName,
            'expected_total': item.expectedTotal,
            'detail_total': item.detailTotal,
            'invoice_identity_matches': item.invoiceIdentityMatches ? 1 : 0,
            'detail_total_internally_consistent':
                item.detailTotalInternallyConsistent ? 1 : 0,
            'detail_total_matches_csv': item.detailTotalMatchesCsv ? 1 : 0,
            'seller_identifier_consistent':
                item.sellerIdentifierConsistent ? 1 : 0,
            'line_items_json': encodeCloudInvoiceLineItems(
              item.lineItems
                  .map((lineItem) => lineItem.toCandidateItem())
                  .toList(growable: false),
            ),
            'payload_version': canonicalCloudInvoicePayloadVersion,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return accepted.length;
  }

  Future<Map<String, OfficialInvoiceDetailEnrichment>> loadByInvoiceNumbers(
    Iterable<String> invoiceNumbers,
  ) async {
    final normalized = invoiceNumbers
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) {
      return const <String, OfficialInvoiceDetailEnrichment>{};
    }
    final db = await _databaseProvider();
    await createCanonicalProductionV15Tables(db);
    final placeholders = List.filled(normalized.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM cloud_invoice_detail_enrichments '
      'WHERE invoice_number IN ($placeholders)',
      normalized.toList(growable: false),
    );
    return <String, OfficialInvoiceDetailEnrichment>{
      for (final row in rows)
        row['invoice_number'] as String: _fromRow(row),
    };
  }

  OfficialInvoiceDetailEnrichment _fromRow(Map<String, Object?> row) {
    final lineItems = decodeCloudInvoiceLineItems(
      row['line_items_json'] as String,
    )
        .map(
          (item) => OfficialInvoiceDetailLineItem(
            name: item.name,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            amount: item.amount,
          ),
        )
        .toList(growable: false);
    return OfficialInvoiceDetailEnrichment(
      requestedInvoiceNumber: row['invoice_number'] as String,
      invoiceNumber: row['invoice_number'] as String,
      selectorProfileVersion:
          (row['selector_profile_version'] as num).toInt(),
      fetchedAt: DateTime.parse(row['fetched_at'] as String),
      success: true,
      invoiceIdentityMatches:
          (row['invoice_identity_matches'] as num).toInt() == 1,
      detailTotalInternallyConsistent:
          (row['detail_total_internally_consistent'] as num).toInt() == 1,
      detailTotalMatchesCsv:
          (row['detail_total_matches_csv'] as num).toInt() == 1,
      sellerIdentifierConsistent:
          (row['seller_identifier_consistent'] as num).toInt() == 1,
      lineItems: lineItems,
      exactTimestamp: DateTime.parse(row['exact_timestamp'] as String),
      currencyCode: row['currency_code'] as String,
      officialStatus: row['official_status'] as String?,
      sellerIdentifier: row['seller_identifier'] as String?,
      sellerName: row['seller_name'] as String?,
      expectedTotal: (row['expected_total'] as num).toDouble(),
      detailTotal: (row['detail_total'] as num).toDouble(),
    );
  }
}
