import 'package:sqflite/sqflite.dart';

import 'canonical_cloud_invoice_persistence_codec.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_persistence_ports.dart';
import 'cloud_invoice_reconciliation_models.dart';

class CanonicalCloudInvoiceOperationAdapter
    implements CloudInvoiceOperationPersistencePort {
  CanonicalCloudInvoiceOperationAdapter(
    this.db, {
    this.faultInjector,
  });

  final DatabaseExecutor db;
  final Future<void> Function(String checkpoint)? faultInjector;

  @override
  Future<CloudInvoiceOperationRecord?> loadOperation(String operationKey) async {
    final rows = await db.query(
      'cloud_invoice_operations',
      where: 'operation_key = ?',
      whereArgs: <Object?>[operationKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CloudInvoiceOperationRecord(
      operationKey: _requiredString(row, 'operation_key'),
      requestFingerprint: _requiredString(row, 'request_fingerprint'),
      action: _enumByName(
        CloudInvoiceReconciliationOutcome.values,
        _requiredString(row, 'action'),
        'operation.action',
      ),
      status: _enumByName(
        CloudInvoicePersistenceStatus.values,
        _requiredString(row, 'status'),
        'operation.status',
      ),
      candidateReference: _requiredString(row, 'candidate_reference'),
      transactionId: row['transaction_id'] as String?,
      accountId: row['account_id'] as String?,
      merchantId: row['merchant_id'] as String?,
      draftId: row['draft_id'] as String?,
      rollbackToken: row['rollback_token'] as String?,
      failureMessage: row['failure_message'] as String?,
      createdAt: _requiredDate(row['created_at'], 'operation.created_at'),
      updatedAt: _requiredDate(row['updated_at'], 'operation.updated_at'),
    );
  }

  @override
  Future<void> saveOperation(CloudInvoiceOperationRecord operation) async {
    await _fault('before_save_operation');
    await db.insert(
      'cloud_invoice_operations',
      <String, Object?>{
        'operation_key': operation.operationKey,
        'request_fingerprint': operation.requestFingerprint,
        'action': operation.action.name,
        'status': operation.status.name,
        'candidate_reference': operation.candidateReference,
        'transaction_id': operation.transactionId,
        'account_id': operation.accountId,
        'merchant_id': operation.merchantId,
        'draft_id': operation.draftId,
        'rollback_token': operation.rollbackToken,
        'failure_message': operation.failureMessage,
        'created_at': operation.createdAt.toUtc().toIso8601String(),
        'updated_at': operation.updatedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _fault('after_save_operation');
  }

  Future<void> removeOperation(String operationKey) async {
    await _fault('before_remove_operation');
    await db.delete(
      'cloud_invoice_operations',
      where: 'operation_key = ?',
      whereArgs: <Object?>[operationKey],
    );
    await _fault('after_remove_operation');
  }

  @override
  Future<void> saveBeforeImage(
    CloudInvoiceBeforeImageRecord beforeImage,
  ) async {
    await _fault('before_save_before_image');
    await db.insert(
      'cloud_invoice_before_images',
      <String, Object?>{
        'rollback_token': beforeImage.rollbackToken,
        'operation_key': beforeImage.operationKey,
        'transaction_fingerprint': beforeImage.transactionFingerprint,
        'transaction_json': encodeTransactionBeforeImage(beforeImage.transaction),
        'payload_version': canonicalCloudInvoicePayloadVersion,
        'created_at': beforeImage.createdAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _fault('after_save_before_image');
  }

  @override
  Future<CloudInvoiceBeforeImageRecord?> loadBeforeImage(
    String rollbackToken,
  ) async {
    final rows = await db.query(
      'cloud_invoice_before_images',
      where: 'rollback_token = ?',
      whereArgs: <Object?>[rollbackToken],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final version = (row['payload_version'] as num?)?.toInt();
    if (version != canonicalCloudInvoicePayloadVersion) {
      throw FormatException('BEFORE_IMAGE_VERSION_UNSUPPORTED:$version');
    }
    return CloudInvoiceBeforeImageRecord(
      rollbackToken: _requiredString(row, 'rollback_token'),
      operationKey: _requiredString(row, 'operation_key'),
      transaction: decodeTransactionBeforeImage(
        _requiredString(row, 'transaction_json'),
      ),
      transactionFingerprint: _requiredString(
        row,
        'transaction_fingerprint',
      ),
      createdAt: _requiredDate(row['created_at'], 'before_image.created_at'),
    );
  }

  @override
  Future<void> appendAudit(CloudInvoiceAuditRecord audit) async {
    await _fault('before_append_audit');
    await db.insert(
      'cloud_invoice_audits',
      <String, Object?>{
        'id': audit.id,
        'operation_key': audit.operationKey,
        'action': audit.action.name,
        'status': audit.status.name,
        'candidate_reference': audit.candidateReference,
        'transaction_id': audit.transactionId,
        'account_id': audit.accountId,
        'merchant_id': audit.merchantId,
        'rollback_token': audit.rollbackToken,
        'message': audit.message,
        'created_at': audit.createdAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _fault('after_append_audit');
  }

  Future<void> removeBeforeImagesForOperation(String operationKey) async {
    await db.delete(
      'cloud_invoice_before_images',
      where: 'operation_key = ?',
      whereArgs: <Object?>[operationKey],
    );
  }

  Future<void> _fault(String checkpoint) async {
    await faultInjector?.call(checkpoint);
  }
}

T _enumByName<T extends Enum>(
  Iterable<T> values,
  String name,
  String field,
) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('ENUM_UNSUPPORTED:$field:$name');
}

String _requiredString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('REQUIRED_DATABASE_STRING_MISSING:$key');
  }
  return value;
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
