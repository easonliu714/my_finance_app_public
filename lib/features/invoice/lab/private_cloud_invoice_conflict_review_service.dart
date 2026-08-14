import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../database/production_database_coordinator.dart';
import '../../../database/production_schema_v16.dart';
import '../../account/account_record.dart';
import '../../transaction/transaction_ledger_refresh_signal.dart';
import '../../transaction/transaction_record.dart';
import '../../transaction/transaction_type.dart';
import '../cloud_invoice_candidate.dart';
import 'canonical_cloud_invoice_persistence_codec.dart';
import 'cloud_invoice_reconciliation_models.dart';

enum PrivateCloudInvoiceConflictResolutionAction {
  keepExisting,
  attachMetadata,
  updateOfficialFields,
  keepSeparate,
}

extension PrivateCloudInvoiceConflictResolutionActionLabel
    on PrivateCloudInvoiceConflictResolutionAction {
  String get label => switch (this) {
        PrivateCloudInvoiceConflictResolutionAction.keepExisting =>
          '保留既有交易並關閉此草稿',
        PrivateCloudInvoiceConflictResolutionAction.attachMetadata =>
          '只掛上發票明細，不修改交易',
        PrivateCloudInvoiceConflictResolutionAction.updateOfficialFields =>
          '以官方金額／時間／商家更新，保留分類等設定',
        PrivateCloudInvoiceConflictResolutionAction.keepSeparate =>
          '兩筆皆保留並另建新交易',
      };

  String get description => switch (this) {
        PrivateCloudInvoiceConflictResolutionAction.keepExisting =>
          '不修改正式交易，也不掛上發票 metadata；只記錄人工決策並關閉本草稿。',
        PrivateCloudInvoiceConflictResolutionAction.attachMetadata =>
          '正式交易所有欄位保持不變，只新增發票號碼、賣方與品項明細關聯。',
        PrivateCloudInvoiceConflictResolutionAction.updateOfficialFields =>
          '更新金額、時間、商家與幣別；帳戶、分類、成員、標籤與既有備註保留。',
        PrivateCloudInvoiceConflictResolutionAction.keepSeparate =>
          '既有交易完全不變；使用官方明細另建新交易，必須使用草稿覆核時明確選定的有效帳戶，分類、成員與標籤沿用候選交易。',
      };
}

class PrivateCloudInvoiceConflictDraft {
  const PrivateCloudInvoiceConflictDraft({
    required this.id,
    required this.operationKey,
    required this.candidateReference,
    required this.accountId,
    required this.accountName,
    required this.amount,
    required this.invoiceDate,
    required this.currencyCode,
    required this.timePrecision,
    required this.timeSource,
    required this.currencySource,
    required this.invoiceNumber,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.taxAmount,
    required this.lineItems,
    required this.lineItemsJson,
    required this.payloadVersion,
    required this.createdAt,
  });

  final String id;
  final String operationKey;
  final String candidateReference;
  final String accountId;
  final String accountName;
  final double amount;
  final DateTime invoiceDate;
  final String? currencyCode;
  final CloudInvoiceTimePrecision timePrecision;
  final CloudInvoiceTimeSource timeSource;
  final CloudInvoiceCurrencySource currencySource;
  final String invoiceNumber;
  final String sellerIdentifier;
  final String sellerName;
  final double? taxAmount;
  final List<CloudInvoiceLineItem> lineItems;
  final String lineItemsJson;
  final int payloadVersion;
  final DateTime createdAt;

  String get fingerprint => <String>[
        id,
        operationKey,
        candidateReference,
        accountId,
        accountName,
        amount.toStringAsFixed(6),
        invoiceDate.toIso8601String(),
        currencyCode ?? '',
        timePrecision.name,
        timeSource.name,
        currencySource.name,
        invoiceNumber,
        sellerIdentifier,
        sellerName,
        taxAmount?.toStringAsFixed(6) ?? '',
        lineItemsJson,
        payloadVersion.toString(),
      ].join('||');
}

class PrivateCloudInvoiceConflictReviewItem {
  const PrivateCloudInvoiceConflictReviewItem({
    required this.draft,
    required this.existingTransaction,
    required this.existingHasInvoiceMetadata,
  });

  final PrivateCloudInvoiceConflictDraft draft;
  final TransactionRecord existingTransaction;
  final bool existingHasInvoiceMetadata;

  bool get amountDiffers =>
      (draft.amount - existingTransaction.amount).abs() > 0.005;

  bool get timestampDiffers =>
      draft.invoiceDate.toUtc() != existingTransaction.occurredAt.toUtc();

  bool get merchantDiffers =>
      _normalizedText(draft.sellerName) !=
      _normalizedText(existingTransaction.merchantName);

  bool get currencyDiffers {
    final official = draft.currencyCode?.trim().toUpperCase();
    return official != null &&
        official.isNotEmpty &&
        official != existingTransaction.currency.code;
  }

  List<String> get differenceLabels => <String>[
        if (amountDiffers) '金額不同',
        if (timestampDiffers) '時間不同',
        if (merchantDiffers) '商家不同',
        if (currencyDiffers) '幣別不同',
        if (!existingHasInvoiceMetadata) '既有交易尚無發票關聯',
        '保留分類：${existingTransaction.category}',
        '保留成員：${existingTransaction.memberName}',
        '保留標籤：${existingTransaction.tagName}',
      ];
}

class PrivateCloudInvoiceConflictResolutionDecision {
  const PrivateCloudInvoiceConflictResolutionDecision({
    required this.draftId,
    required this.transactionId,
    required this.action,
  });

  final String draftId;
  final String transactionId;
  final PrivateCloudInvoiceConflictResolutionAction action;
}

enum PrivateCloudInvoiceConflictResolutionStatus { committed, replay, rejected }

class PrivateCloudInvoiceConflictResolutionResult {
  const PrivateCloudInvoiceConflictResolutionResult({
    required this.draftId,
    required this.transactionId,
    required this.status,
    required this.message,
  });

  final String draftId;
  final String transactionId;
  final PrivateCloudInvoiceConflictResolutionStatus status;
  final String message;
}

class PrivateCloudInvoiceConflictResolutionSummary {
  const PrivateCloudInvoiceConflictResolutionSummary({required this.results});

  final List<PrivateCloudInvoiceConflictResolutionResult> results;

  int get committedCount => results
      .where(
        (result) =>
            result.status ==
            PrivateCloudInvoiceConflictResolutionStatus.committed,
      )
      .length;

  int get replayCount => results
      .where(
        (result) =>
            result.status == PrivateCloudInvoiceConflictResolutionStatus.replay,
      )
      .length;

  int get rejectedCount => results.length - committedCount - replayCount;
}

abstract interface class PrivateCloudInvoiceConflictReviewPort {
  Future<List<PrivateCloudInvoiceConflictReviewItem>> loadReviewItems(
    Map<String, String> conflictTransactionByDraftId,
  );

  Future<PrivateCloudInvoiceConflictResolutionSummary> resolveMany({
    required List<PrivateCloudInvoiceConflictResolutionDecision> decisions,
    required bool finalConfirmation,
  });
}

class PrivateCloudInvoiceConflictReviewService
    implements PrivateCloudInvoiceConflictReviewPort {
  PrivateCloudInvoiceConflictReviewService({
    Future<Database> Function()? databaseProvider,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
    void Function()? onLedgerChanged,
  })  : _databaseProvider = databaseProvider ??
            (() => ProductionDatabaseCoordinator.instance.database),
        _uuid = uuid,
        _clock = clock ?? DateTime.now,
        _onLedgerChanged =
            onLedgerChanged ?? TransactionLedgerRefreshSignal.instance.emit;

  final Future<Database> Function() _databaseProvider;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final void Function() _onLedgerChanged;

  @override
  Future<List<PrivateCloudInvoiceConflictReviewItem>> loadReviewItems(
    Map<String, String> conflictTransactionByDraftId,
  ) async {
    final db = await _databaseProvider();
    await createCanonicalProductionV16Tables(db);
    final items = <PrivateCloudInvoiceConflictReviewItem>[];

    for (final entry in conflictTransactionByDraftId.entries) {
      final promoted = await db.query(
        'cloud_invoice_draft_promotions',
        columns: const <String>['draft_id'],
        where: 'draft_id = ?',
        whereArgs: <Object?>[entry.key],
        limit: 1,
      );
      if (promoted.isNotEmpty) continue;

      final resolved = await db.query(
        'cloud_invoice_operations',
        columns: const <String>['operation_key'],
        where:
            "draft_id = ? AND status = 'committed' AND operation_key LIKE 'cloud-invoice-conflict:%'",
        whereArgs: <Object?>[entry.key],
        limit: 1,
      );
      if (resolved.isNotEmpty) continue;

      final draftRows = await db.query(
        'cloud_invoice_drafts',
        where: 'id = ?',
        whereArgs: <Object?>[entry.key],
        limit: 1,
      );
      final transactionRows = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>[entry.value],
        limit: 1,
      );
      if (draftRows.isEmpty || transactionRows.isEmpty) continue;

      final metadataRows = await db.query(
        'cloud_invoice_metadata_links',
        columns: const <String>['id'],
        where: 'transaction_id = ?',
        whereArgs: <Object?>[entry.value],
        limit: 1,
      );
      items.add(
        PrivateCloudInvoiceConflictReviewItem(
          draft: _draftFromRow(draftRows.single),
          existingTransaction: TransactionRecord.fromMap(
            transactionRows.single,
          ),
          existingHasInvoiceMetadata: metadataRows.isNotEmpty,
        ),
      );
    }

    items.sort(
      (left, right) =>
          right.draft.invoiceDate.compareTo(left.draft.invoiceDate),
    );
    return List.unmodifiable(items);
  }

  @override
  Future<PrivateCloudInvoiceConflictResolutionSummary> resolveMany({
    required List<PrivateCloudInvoiceConflictResolutionDecision> decisions,
    required bool finalConfirmation,
  }) async {
    if (!finalConfirmation) {
      throw StateError('CONFLICT_RESOLUTION_CONFIRMATION_REQUIRED');
    }
    if (decisions.isEmpty) {
      throw StateError('NO_CONFLICT_RESOLUTION_SELECTED');
    }

    final results = <PrivateCloudInvoiceConflictResolutionResult>[];
    for (final decision in decisions) {
      results.add(await _resolve(decision));
    }
    final summary = PrivateCloudInvoiceConflictResolutionSummary(
      results: List.unmodifiable(results),
    );
    if (summary.committedCount > 0) {
      _onLedgerChanged();
    }
    return summary;
  }

  Future<PrivateCloudInvoiceConflictResolutionResult> _resolve(
    PrivateCloudInvoiceConflictResolutionDecision decision,
  ) async {
    final db = await _databaseProvider();
    await createCanonicalProductionV16Tables(db);
    return db.transaction((transaction) async {
      final existingPromotion = await transaction.query(
        'cloud_invoice_draft_promotions',
        columns: const <String>['transaction_id'],
        where: 'draft_id = ?',
        whereArgs: <Object?>[decision.draftId],
        limit: 1,
      );
      if (existingPromotion.isNotEmpty) {
        return PrivateCloudInvoiceConflictResolutionResult(
          draftId: decision.draftId,
          transactionId: existingPromotion.single['transaction_id'] as String,
          status: PrivateCloudInvoiceConflictResolutionStatus.replay,
          message: 'CONFLICT_RESOLUTION_ALREADY_APPLIED',
        );
      }

      final existingResolution = await transaction.query(
        'cloud_invoice_operations',
        columns: const <String>['transaction_id'],
        where:
            "draft_id = ? AND status = 'committed' AND operation_key LIKE 'cloud-invoice-conflict:%'",
        whereArgs: <Object?>[decision.draftId],
        limit: 1,
      );
      if (existingResolution.isNotEmpty) {
        return PrivateCloudInvoiceConflictResolutionResult(
          draftId: decision.draftId,
          transactionId:
              existingResolution.single['transaction_id'] as String? ??
                  decision.transactionId,
          status: PrivateCloudInvoiceConflictResolutionStatus.replay,
          message: 'CONFLICT_RESOLUTION_ALREADY_APPLIED',
        );
      }

      final draftRows = await transaction.query(
        'cloud_invoice_drafts',
        where: 'id = ?',
        whereArgs: <Object?>[decision.draftId],
        limit: 1,
      );
      final transactionRows = await transaction.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>[decision.transactionId],
        limit: 1,
      );
      if (draftRows.isEmpty || transactionRows.isEmpty) {
        return _rejected(decision, 'CONFLICT_REVIEW_TARGET_MISSING');
      }

      final draft = _draftFromRow(draftRows.single);
      final existing = TransactionRecord.fromMap(transactionRows.single);
      if (existing.type != TransactionType.expense) {
        return _rejected(decision, 'CONFLICT_TARGET_NOT_EXPENSE');
      }

      AccountRecord? separateAccount;
      if (decision.action ==
          PrivateCloudInvoiceConflictResolutionAction.keepSeparate) {
        final resolvedAccountId = draft.accountId.trim();
        if (resolvedAccountId.isEmpty) {
          return _rejected(decision, 'ACCOUNT_REQUIRED_FOR_NEW_TRANSACTION');
        }
        final accountRows = await transaction.query(
          'accounts',
          where: 'id = ? AND is_archived = 0',
          whereArgs: <Object?>[resolvedAccountId],
          limit: 1,
        );
        if (accountRows.isEmpty) {
          return _rejected(
            decision,
            'ACCOUNT_NOT_AVAILABLE_FOR_NEW_TRANSACTION',
          );
        }
        separateAccount = AccountRecord.fromMap(accountRows.single);
      }

      final normalizedInvoice = _normalizedInvoiceNumber(draft.invoiceNumber);
      final invoiceLinks = await transaction.query(
        'cloud_invoice_metadata_links',
        columns: const <String>['transaction_id'],
        where: 'UPPER(invoice_number) = ?',
        whereArgs: <Object?>[normalizedInvoice],
      );
      if (decision.action ==
              PrivateCloudInvoiceConflictResolutionAction.keepSeparate &&
          invoiceLinks.isNotEmpty) {
        return _rejected(
          decision,
          'INVOICE_ALREADY_LINKED_TO_OTHER_TRANSACTION',
        );
      }

      final modifiesExisting = decision.action ==
              PrivateCloudInvoiceConflictResolutionAction.attachMetadata ||
          decision.action ==
              PrivateCloudInvoiceConflictResolutionAction.updateOfficialFields;
      if (modifiesExisting) {
        final otherPromotion = await transaction.query(
          'cloud_invoice_draft_promotions',
          columns: const <String>['draft_id'],
          where: 'transaction_id = ? AND draft_id <> ?',
          whereArgs: <Object?>[decision.transactionId, decision.draftId],
          limit: 1,
        );
        if (otherPromotion.isNotEmpty) {
          return _rejected(
            decision,
            'TRANSACTION_ALREADY_LINKED_TO_OTHER_DRAFT',
          );
        }
        if (invoiceLinks.any(
          (row) => row['transaction_id'] != decision.transactionId,
        )) {
          return _rejected(
            decision,
            'INVOICE_ALREADY_LINKED_TO_OTHER_TRANSACTION',
          );
        }

        final targetInvoiceLinks = await transaction.query(
          'cloud_invoice_metadata_links',
          columns: const <String>['invoice_number'],
          where: 'transaction_id = ?',
          whereArgs: <Object?>[decision.transactionId],
        );
        final hasDifferentInvoice = targetInvoiceLinks.any((row) {
          final linkedInvoice = _normalizedInvoiceNumber(
            row['invoice_number'] as String? ?? '',
          );
          return linkedInvoice.isNotEmpty && linkedInvoice != normalizedInvoice;
        });
        if (hasDifferentInvoice) {
          return _rejected(
            decision,
            'TRANSACTION_ALREADY_LINKED_TO_OTHER_INVOICE',
          );
        }
      }

      final now = _clock().toUtc();
      final operationKey =
          'cloud-invoice-conflict:${draft.id}:${decision.action.name}';
      String? rollbackToken;
      var resolvedTransaction = existing;

      switch (decision.action) {
        case PrivateCloudInvoiceConflictResolutionAction.keepExisting:
          break;
        case PrivateCloudInvoiceConflictResolutionAction.attachMetadata:
          await _insertMetadataIfMissing(
            transaction,
            draft: draft,
            target: existing,
            operationKey: operationKey,
            now: now,
          );
          break;
        case PrivateCloudInvoiceConflictResolutionAction.updateOfficialFields:
          rollbackToken = 'cloud-invoice-conflict-rollback:${_uuid.v4()}';
          await transaction.insert(
            'cloud_invoice_before_images',
            <String, Object?>{
              'rollback_token': rollbackToken,
              'operation_key': operationKey,
              'transaction_fingerprint': _transactionFingerprint(existing),
              'transaction_json': encodeTransactionBeforeImage(existing),
              'payload_version': canonicalCloudInvoicePayloadVersion,
              'created_at': now.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          resolvedTransaction = _withOfficialFields(existing, draft);
          final changed = await transaction.update(
            'transactions',
            resolvedTransaction.toMap(),
            where: 'id = ?',
            whereArgs: <Object?>[existing.id],
          );
          if (changed != 1) {
            throw StateError('CONFLICT_TRANSACTION_UPDATE_FAILED');
          }
          await _insertMetadataIfMissing(
            transaction,
            draft: draft,
            target: resolvedTransaction,
            operationKey: operationKey,
            now: now,
          );
          break;
        case PrivateCloudInvoiceConflictResolutionAction.keepSeparate:
          resolvedTransaction = _buildSeparateTransaction(
            existing,
            draft,
            account: separateAccount!,
          );
          await transaction.insert(
            'transactions',
            resolvedTransaction.toMap(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          await _insertMetadataIfMissing(
            transaction,
            draft: draft,
            target: resolvedTransaction,
            operationKey: operationKey,
            now: now,
          );
          break;
      }

      if (decision.action !=
          PrivateCloudInvoiceConflictResolutionAction.keepExisting) {
        await transaction.insert(
          'cloud_invoice_draft_promotions',
          <String, Object?>{
            'draft_id': draft.id,
            'promotion_key': operationKey,
            'draft_operation_key': draft.operationKey,
            'draft_fingerprint': draft.fingerprint,
            'transaction_id': resolvedTransaction.id,
            'category': resolvedTransaction.category,
            'member_name': resolvedTransaction.memberName,
            'tag_name': resolvedTransaction.tagName,
            'note': 'conflict-resolution:${decision.action.name}',
            'created_at': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await transaction.insert(
        'cloud_invoice_operations',
        <String, Object?>{
          'operation_key': operationKey,
          'request_fingerprint':
              '${draft.fingerprint}||${existing.id}||${decision.action.name}',
          'action': _persistenceAction(decision.action).name,
          'status': 'committed',
          'candidate_reference': draft.candidateReference,
          'transaction_id': resolvedTransaction.id,
          'account_id': draft.accountId,
          'merchant_id': null,
          'draft_id': draft.id,
          'rollback_token': rollbackToken,
          'failure_message': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await transaction.insert(
        'cloud_invoice_audits',
        <String, Object?>{
          'id': 'cloud-invoice-audit-${_uuid.v4()}',
          'operation_key': operationKey,
          'action': _persistenceAction(decision.action).name,
          'status': 'committed',
          'candidate_reference': draft.candidateReference,
          'transaction_id': resolvedTransaction.id,
          'account_id': draft.accountId,
          'merchant_id': null,
          'rollback_token': rollbackToken,
          'message': 'CONFLICT_RESOLUTION_COMMITTED',
          'created_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return PrivateCloudInvoiceConflictResolutionResult(
        draftId: draft.id,
        transactionId: resolvedTransaction.id,
        status: PrivateCloudInvoiceConflictResolutionStatus.committed,
        message: 'CONFLICT_RESOLUTION_COMMITTED',
      );
    });
  }

  Future<void> _insertMetadataIfMissing(
    DatabaseExecutor db, {
    required PrivateCloudInvoiceConflictDraft draft,
    required TransactionRecord target,
    required String operationKey,
    required DateTime now,
  }) async {
    final existing = await db.query(
      'cloud_invoice_metadata_links',
      columns: const <String>['id'],
      where: 'transaction_id = ? AND UPPER(invoice_number) = ?',
      whereArgs: <Object?>[
        target.id,
        _normalizedInvoiceNumber(draft.invoiceNumber),
      ],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    await db.insert(
      'cloud_invoice_metadata_links',
      <String, Object?>{
        'id': 'cloud-invoice-metadata-${_uuid.v4()}',
        'operation_key': '$operationKey:metadata',
        'transaction_id': target.id,
        'candidate_reference': draft.candidateReference,
        'invoice_number': draft.invoiceNumber,
        'seller_identifier': draft.sellerIdentifier,
        'seller_name': draft.sellerName,
        'invoice_date': draft.invoiceDate.toIso8601String(),
        'time_precision': draft.timePrecision.name,
        'time_source': draft.timeSource.name,
        'currency_code': draft.currencyCode ?? target.currency.code,
        'currency_source': draft.currencySource.name,
        'tax_amount': draft.taxAmount,
        'merchant_id': null,
        'line_items_json': draft.lineItemsJson,
        'payload_version': draft.payloadVersion,
        'created_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  TransactionRecord _withOfficialFields(
    TransactionRecord existing,
    PrivateCloudInvoiceConflictDraft draft,
  ) {
    final nextCurrency = currencyFromCode(
      draft.currencyCode ?? existing.currency.code,
    );
    final nextRate = nextCurrency == existing.currency
        ? existing.exchangeRateToBase
        : nextCurrency.defaultRateToTwd;
    final sellerName = draft.sellerName.trim();
    final invoiceToken = '發票：${draft.invoiceNumber}';
    final note = existing.note.contains(invoiceToken)
        ? existing.note
        : <String>[
            if (existing.note.trim().isNotEmpty) existing.note.trim(),
            invoiceToken,
          ].join('｜');

    return existing.copyWith(
      amount: draft.amount,
      occurredAt: draft.invoiceDate,
      merchantName: sellerName.isEmpty ? existing.merchantName : sellerName,
      note: note,
      currency: nextCurrency,
      exchangeRateToBase: nextRate,
    );
  }

  TransactionRecord _buildSeparateTransaction(
    TransactionRecord existing,
    PrivateCloudInvoiceConflictDraft draft, {
    required AccountRecord account,
  }) {
    final currency = currencyFromCode(
      draft.currencyCode ?? account.currency.code,
    );
    final sellerName = draft.sellerName.trim();
    return TransactionRecord(
      id: _uuid.v4(),
      type: TransactionType.expense,
      amount: draft.amount,
      category: existing.category,
      occurredAt: draft.invoiceDate,
      accountName: account.displayName,
      memberName: existing.memberName,
      merchantName: sellerName.isEmpty ? '未提供商家' : sellerName,
      tagName: existing.tagName,
      note: '發票：${draft.invoiceNumber}',
      currency: currency,
      exchangeRateToBase: currency.defaultRateToTwd,
    );
  }

  PrivateCloudInvoiceConflictResolutionResult _rejected(
    PrivateCloudInvoiceConflictResolutionDecision decision,
    String message,
  ) {
    return PrivateCloudInvoiceConflictResolutionResult(
      draftId: decision.draftId,
      transactionId: decision.transactionId,
      status: PrivateCloudInvoiceConflictResolutionStatus.rejected,
      message: message,
    );
  }

  PrivateCloudInvoiceConflictDraft _draftFromRow(Map<String, Object?> row) {
    final payloadVersion = (row['payload_version'] as num?)?.toInt();
    if (payloadVersion != canonicalCloudInvoicePayloadVersion) {
      throw FormatException(
        'DRAFT_PAYLOAD_VERSION_UNSUPPORTED:$payloadVersion',
      );
    }
    final lineItemsJson = row['line_items_json'] as String;
    return PrivateCloudInvoiceConflictDraft(
      id: row['id'] as String,
      operationKey: row['operation_key'] as String,
      candidateReference: row['candidate_reference'] as String,
      accountId: row['account_id'] as String,
      accountName: row['account_name'] as String,
      amount: (row['amount'] as num).toDouble(),
      invoiceDate: DateTime.parse(row['invoice_date'] as String),
      currencyCode: row['currency_code'] as String?,
      timePrecision: CloudInvoiceTimePrecision.values.byName(
        row['time_precision'] as String? ?? 'dateOnly',
      ),
      timeSource: CloudInvoiceTimeSource.values.byName(
        row['time_source'] as String? ?? 'unknown',
      ),
      currencySource: CloudInvoiceCurrencySource.values.byName(
        row['currency_source'] as String? ?? 'unknown',
      ),
      invoiceNumber: row['invoice_number'] as String,
      sellerIdentifier: row['seller_identifier'] as String,
      sellerName: row['seller_name'] as String,
      taxAmount: (row['tax_amount'] as num?)?.toDouble(),
      lineItems: decodeCloudInvoiceLineItems(lineItemsJson),
      lineItemsJson: lineItemsJson,
      payloadVersion: payloadVersion!,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

CloudInvoiceReconciliationOutcome _persistenceAction(
  PrivateCloudInvoiceConflictResolutionAction action,
) {
  return switch (action) {
    PrivateCloudInvoiceConflictResolutionAction.keepExisting =>
      CloudInvoiceReconciliationOutcome.exactDuplicate,
    PrivateCloudInvoiceConflictResolutionAction.attachMetadata =>
      CloudInvoiceReconciliationOutcome.enrichExisting,
    PrivateCloudInvoiceConflictResolutionAction.updateOfficialFields =>
      CloudInvoiceReconciliationOutcome.replaceExisting,
    PrivateCloudInvoiceConflictResolutionAction.keepSeparate =>
      CloudInvoiceReconciliationOutcome.keepSeparate,
  };
}

String _normalizedText(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();

String _normalizedInvoiceNumber(String value) => value.trim().toUpperCase();

String _transactionFingerprint(TransactionRecord transaction) => transaction
    .toMap()
    .entries
    .map((entry) => '${entry.key}=${entry.value}')
    .join('|');
