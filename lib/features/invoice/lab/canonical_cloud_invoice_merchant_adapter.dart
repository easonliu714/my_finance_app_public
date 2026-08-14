import 'package:sqflite/sqflite.dart';

import '../../merchant/merchant_record.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_persistence_ports.dart';

class CanonicalCloudInvoiceMerchantAdapter
    implements CloudInvoiceMerchantPersistencePort {
  CanonicalCloudInvoiceMerchantAdapter(
    this.db, {
    this.faultInjector,
  });

  final DatabaseExecutor db;
  final Future<void> Function(String checkpoint)? faultInjector;
  final Map<String, String> _createdMerchantOperations = <String, String>{};

  @override
  Future<MerchantRecord?> findByNormalizedName(String normalizedName) async {
    final rows = await db.query(
      'merchants',
      orderBy: 'name COLLATE NOCASE ASC, alias COLLATE NOCASE ASC, id ASC',
    );
    for (final row in rows) {
      final merchant = _merchantFromRow(row);
      if (normalizeMerchantName(merchant.name) == normalizedName ||
          normalizeMerchantName(merchant.displayName) == normalizedName) {
        return merchant;
      }
    }
    return null;
  }

  @override
  Future<CloudInvoiceMerchantCreationResult> createMerchant({
    required MerchantRecord merchant,
    required String operationKey,
  }) async {
    final existing = await findByNormalizedName(
      normalizeMerchantName(merchant.name),
    );
    if (existing != null) {
      return CloudInvoiceMerchantCreationResult(
        merchant: existing,
        createdForOperation: false,
      );
    }

    await _fault('before_create_merchant');
    await db.insert(
      'merchants',
      _merchantToRow(merchant),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _createdMerchantOperations[merchant.id] = operationKey;
    await _fault('after_create_merchant');
    return CloudInvoiceMerchantCreationResult(
      merchant: merchant,
      createdForOperation: true,
    );
  }

  @override
  Future<bool> hasExternalReferences(String merchantId) async {
    final operationKey = _createdMerchantOperations[merchantId];
    final draftCount = await _countReferences(
      table: 'cloud_invoice_drafts',
      merchantId: merchantId,
      operationKey: operationKey,
    );
    final linkCount = await _countReferences(
      table: 'cloud_invoice_metadata_links',
      merchantId: merchantId,
      operationKey: operationKey,
    );
    return draftCount + linkCount > 0;
  }

  @override
  Future<void> compensateCreatedMerchant({
    required String merchantId,
    required String operationKey,
  }) async {
    if (_createdMerchantOperations[merchantId] != operationKey) return;
    if (await hasExternalReferences(merchantId)) return;
    await db.delete(
      'merchants',
      where: 'id = ?',
      whereArgs: <Object?>[merchantId],
    );
    _createdMerchantOperations.remove(merchantId);
  }

  Future<int> _countReferences({
    required String table,
    required String merchantId,
    required String? operationKey,
  }) async {
    final rows = await db.query(
      table,
      columns: const <String>['id'],
      where: operationKey == null
          ? 'merchant_id = ?'
          : 'merchant_id = ? AND operation_key <> ?',
      whereArgs: operationKey == null
          ? <Object?>[merchantId]
          : <Object?>[merchantId, operationKey],
    );
    return rows.length;
  }

  MerchantRecord _merchantFromRow(Map<String, Object?> row) {
    return MerchantRecord(
      id: row['id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      alias: row['alias'] as String? ?? '',
      note: row['note'] as String? ?? '',
      isArchived: (row['is_archived'] as num? ?? 0).toInt() != 0,
      createdAt: _requiredDate(row['created_at'], 'merchant.created_at'),
      updatedAt: _requiredDate(row['updated_at'], 'merchant.updated_at'),
    );
  }

  Map<String, Object?> _merchantToRow(MerchantRecord merchant) {
    return <String, Object?>{
      'id': merchant.id,
      'name': merchant.name,
      'alias': merchant.alias,
      'note': merchant.note,
      'is_archived': merchant.isArchived ? 1 : 0,
      'created_at': merchant.createdAt.toUtc().toIso8601String(),
      'updated_at': merchant.updatedAt.toUtc().toIso8601String(),
    };
  }

  Future<void> _fault(String checkpoint) async {
    await faultInjector?.call(checkpoint);
  }
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('REQUIRED_DATABASE_DATE_MISSING:$field');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('REQUIRED_DATABASE_DATE_INVALID:$field:$value');
  }
  return parsed;
}
