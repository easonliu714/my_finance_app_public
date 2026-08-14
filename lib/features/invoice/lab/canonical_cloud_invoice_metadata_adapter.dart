import 'package:sqflite/sqflite.dart';

import 'canonical_cloud_invoice_persistence_codec.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_persistence_ports.dart';

class CanonicalCloudInvoiceMetadataAdapter
    implements CloudInvoiceMetadataPersistencePort {
  CanonicalCloudInvoiceMetadataAdapter(
    this.db, {
    this.faultInjector,
  });

  final DatabaseExecutor db;
  final Future<void> Function(String checkpoint)? faultInjector;

  @override
  Future<void> upsertLink(CloudInvoiceMetadataLinkRecord link) async {
    await _fault('before_upsert_metadata_link');
    final row = <String, Object?>{
      'id': link.id,
      'operation_key': link.operationKey,
      'transaction_id': link.transactionId,
      'candidate_reference': link.candidateReference,
      'invoice_number': link.invoiceNumber,
      'seller_identifier': link.sellerIdentifier,
      'seller_name': link.sellerName,
      'invoice_date': link.invoiceDate.toIso8601String(),
      'time_precision': link.timePrecision.name,
      'time_source': link.timeSource.name,
      'currency_code': link.currencyCode,
      'currency_source': link.currencySource.name,
      'tax_amount': link.taxAmount,
      'merchant_id': link.merchantId,
      'line_items_json': encodeCloudInvoiceLineItems(link.lineItems),
      'payload_version': canonicalCloudInvoicePayloadVersion,
      'created_at': link.createdAt.toUtc().toIso8601String(),
    };
    final existing = await db.query(
      'cloud_invoice_metadata_links',
      columns: const <String>['id'],
      where: 'operation_key = ?',
      whereArgs: <Object?>[link.operationKey],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert(
        'cloud_invoice_metadata_links',
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      row['id'] = existing.single['id'];
      await db.update(
        'cloud_invoice_metadata_links',
        row,
        where: 'operation_key = ?',
        whereArgs: <Object?>[link.operationKey],
      );
    }
    await _fault('after_upsert_metadata_link');
  }

  @override
  Future<void> removeLinksForOperation(String operationKey) async {
    await db.delete(
      'cloud_invoice_metadata_links',
      where: 'operation_key = ?',
      whereArgs: <Object?>[operationKey],
    );
  }

  Future<void> _fault(String checkpoint) async {
    await faultInjector?.call(checkpoint);
  }
}
