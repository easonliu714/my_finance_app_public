import 'package:sqflite/sqflite.dart';

import '../../account/account_record.dart';
import '../../transaction/transaction_record.dart';
import '../../transaction/transaction_type.dart';
import 'canonical_cloud_invoice_persistence_codec.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_persistence_ports.dart';

class CanonicalCloudInvoiceTransactionAdapter
    implements CloudInvoiceTransactionPersistencePort {
  CanonicalCloudInvoiceTransactionAdapter(
    this.db, {
    this.faultInjector,
  });

  final DatabaseExecutor db;
  final Future<void> Function(String checkpoint)? faultInjector;

  @override
  Future<TransactionRecord?> loadTransaction(String transactionId) async {
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[transactionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    _validateTransactionRow(row);
    return TransactionRecord.fromMap(row);
  }

  @override
  Future<void> createDraft(CloudInvoiceDraftRecord draft) async {
    await _fault('before_create_draft');
    await db.insert(
      'cloud_invoice_drafts',
      <String, Object?>{
        'id': draft.id,
        'operation_key': draft.operationKey,
        'candidate_reference': draft.candidateReference,
        'account_id': draft.accountId,
        'account_name': draft.accountName,
        'account_resolution_status':
            draft.accountId.trim().isEmpty ? 'unresolved' : 'selected',
        'amount': draft.amount,
        'invoice_date': draft.invoiceDate.toIso8601String(),
        'time_precision': draft.timePrecision.name,
        'time_source': draft.timeSource.name,
        'currency_code': draft.currencyCode,
        'merchant_id': draft.merchantId,
        'invoice_number': draft.invoiceNumber,
        'seller_identifier': draft.sellerIdentifier,
        'seller_name': draft.sellerName,
        'tax_amount': draft.taxAmount,
        'line_items_json': encodeCloudInvoiceLineItems(draft.lineItems),
        'payload_version': canonicalCloudInvoicePayloadVersion,
        'created_at': draft.createdAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _fault('after_create_draft');
  }

  @override
  Future<void> removeDraft({
    required String draftId,
    required String operationKey,
  }) async {
    await db.delete(
      'cloud_invoice_drafts',
      where: 'id = ? AND operation_key = ?',
      whereArgs: <Object?>[draftId, operationKey],
    );
  }

  Future<void> removeDraftsForOperation(String operationKey) async {
    await db.delete(
      'cloud_invoice_drafts',
      where: 'operation_key = ?',
      whereArgs: <Object?>[operationKey],
    );
  }

  @override
  Future<void> replaceTransaction(TransactionRecord transaction) async {
    await _fault('before_replace_transaction');
    final changed = await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[transaction.id],
    );
    if (changed != 1) {
      throw StateError('TRANSACTION_REPLACE_TARGET_MISSING:${transaction.id}');
    }
    await _fault('after_replace_transaction');
  }

  @override
  Future<void> restoreTransaction(TransactionRecord beforeImage) async {
    await _fault('before_restore_transaction');
    final changed = await db.update(
      'transactions',
      beforeImage.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[beforeImage.id],
    );
    if (changed != 1) {
      throw StateError('TRANSACTION_RESTORE_TARGET_MISSING:${beforeImage.id}');
    }
    await _fault('after_restore_transaction');
  }

  Future<void> _fault(String checkpoint) async {
    await faultInjector?.call(checkpoint);
  }
}

class CanonicalCloudInvoiceAccountAdapter
    implements CloudInvoiceAccountPersistencePort {
  const CanonicalCloudInvoiceAccountAdapter(this.db);

  final DatabaseExecutor db;

  @override
  Future<AccountRecord?> loadAccount(String accountId) async {
    final rows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    _validateAccountRow(row);
    return AccountRecord.fromMap(row);
  }
}

void _validateTransactionRow(Map<String, Object?> row) {
  final type = row['type'];
  if (type is! String ||
      !TransactionType.values.any((item) => item.name == type)) {
    throw FormatException('TRANSACTION_TYPE_UNSUPPORTED:$type');
  }
  final currency = row['currency_code'];
  if (currency is! String ||
      !CurrencyCode.values.any((item) => item.code == currency)) {
    throw FormatException('TRANSACTION_CURRENCY_UNSUPPORTED:$currency');
  }
}

void _validateAccountRow(Map<String, Object?> row) {
  final type = row['type'];
  if (type is! String || !AccountType.values.any((item) => item.name == type)) {
    throw FormatException('ACCOUNT_TYPE_UNSUPPORTED:$type');
  }
  final currency = row['currency_code'];
  if (currency is! String ||
      !CurrencyCode.values.any((item) => item.code == currency)) {
    throw FormatException('ACCOUNT_CURRENCY_UNSUPPORTED:$currency');
  }
}
