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
import 'official_invoice_category_suggestion_service.dart';

class PrivateCloudInvoiceDraftCandidate {
  const PrivateCloudInvoiceDraftCandidate({
    required this.id,
    required this.operationKey,
    required this.candidateReference,
    required this.accountId,
    required this.accountName,
    this.accountResolutionStatus = 'selected',
    required this.amount,
    required this.invoiceDate,
    required this.currencyCode,
    this.timePrecision = CloudInvoiceTimePrecision.dateOnly,
    this.timeSource = CloudInvoiceTimeSource.unknown,
    this.currencySource = CloudInvoiceCurrencySource.unknown,
    required this.invoiceNumber,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.lineItems,
    required this.createdAt,
    this.taxAmount,
    this.categorySuggestion,
  });

  final String id;
  final String operationKey;
  final String candidateReference;
  final String accountId;
  final String accountName;
  final String accountResolutionStatus;
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
  final DateTime createdAt;
  final OfficialInvoiceCategorySuggestion? categorySuggestion;

  String get fingerprint => <String>[
        id,
        operationKey,
        candidateReference,
        accountId,
        accountName,
        accountResolutionStatus,
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
        lineItems
            .map(
              (item) => <String>[
                item.name,
                item.amount.toStringAsFixed(6),
                item.quantity?.toString() ?? '',
                item.unitPrice?.toStringAsFixed(6) ?? '',
              ].join(':'),
            )
            .join('|'),
      ].join('||');

  PrivateCloudInvoiceDraftCandidate copyWith({
    String? accountId,
    String? accountName,
    String? accountResolutionStatus,
    OfficialInvoiceCategorySuggestion? categorySuggestion,
  }) {
    return PrivateCloudInvoiceDraftCandidate(
      id: id,
      operationKey: operationKey,
      candidateReference: candidateReference,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      accountResolutionStatus:
          accountResolutionStatus ?? this.accountResolutionStatus,
      amount: amount,
      invoiceDate: invoiceDate,
      currencyCode: currencyCode,
      timePrecision: timePrecision,
      timeSource: timeSource,
      currencySource: currencySource,
      invoiceNumber: invoiceNumber,
      sellerIdentifier: sellerIdentifier,
      sellerName: sellerName,
      lineItems: lineItems,
      createdAt: createdAt,
      taxAmount: taxAmount,
      categorySuggestion: categorySuggestion ?? this.categorySuggestion,
    );
  }
}

class PrivateCloudInvoiceDraftPromotionDecision {
  const PrivateCloudInvoiceDraftPromotionDecision({
    required this.draftId,
    required this.category,
    required this.memberName,
    required this.tagName,
    this.note = '',
    this.accountId,
    this.exchangeRateToBase,
    this.accountRateToBase,
    this.exchangeRateSourceToAccount,
    this.reviewedAccountAmount,
    this.fxSourceName,
    this.fxSourceReference,
    this.fxRequestedDate,
    this.fxEffectiveDate,
    this.fxEffectiveDateTime,
    this.fxSpotBuyToBase,
    this.fxSpotSellToBase,
    this.fxSelectionPolicy,
  });

  final String draftId;
  final String category;
  final String memberName;
  final String tagName;
  final String note;
  final String? accountId;

  /// Source invoice currency to TWD.
  final double? exchangeRateToBase;

  /// Selected account currency to TWD.
  final double? accountRateToBase;

  /// Source invoice currency to selected account currency.
  final double? exchangeRateSourceToAccount;

  /// User-reviewed amount that was actually deducted in the selected account
  /// currency. When provided, this exact rounded amount is used by the ledger.
  final double? reviewedAccountAmount;
  final String? fxSourceName;
  final String? fxSourceReference;
  final DateTime? fxRequestedDate;
  final DateTime? fxEffectiveDate;
  final DateTime? fxEffectiveDateTime;
  final double? fxSpotBuyToBase;
  final double? fxSpotSellToBase;
  final String? fxSelectionPolicy;

  bool get isComplete =>
      category.trim().isNotEmpty &&
      memberName.trim().isNotEmpty &&
      tagName.trim().isNotEmpty;
}

enum PrivateCloudInvoiceDraftPromotionStatus {
  committed,
  replay,
  conflict,
  accountRequired,
  rejected,
}

class PrivateCloudInvoiceDraftPromotionResult {
  const PrivateCloudInvoiceDraftPromotionResult({
    required this.draftId,
    required this.status,
    required this.message,
    this.transactionId,
    this.candidateTransactionIds = const <String>[],
  });

  final String draftId;
  final PrivateCloudInvoiceDraftPromotionStatus status;
  final String message;
  final String? transactionId;
  final List<String> candidateTransactionIds;

  bool get requiresCandidateSelection =>
      status == PrivateCloudInvoiceDraftPromotionStatus.conflict &&
      candidateTransactionIds.length > 1;
}

class PrivateCloudInvoiceDraftPromotionSummary {
  const PrivateCloudInvoiceDraftPromotionSummary({required this.results});

  final List<PrivateCloudInvoiceDraftPromotionResult> results;

  int get committedCount => results
      .where(
        (result) =>
            result.status == PrivateCloudInvoiceDraftPromotionStatus.committed,
      )
      .length;

  int get replayCount => results
      .where(
        (result) =>
            result.status == PrivateCloudInvoiceDraftPromotionStatus.replay,
      )
      .length;

  int get conflictCount => results
      .where(
        (result) =>
            result.status == PrivateCloudInvoiceDraftPromotionStatus.conflict,
      )
      .length;

  int get accountRequiredCount => results
      .where(
        (result) => result.status ==
            PrivateCloudInvoiceDraftPromotionStatus.accountRequired,
      )
      .length;

  int get rejectedCount => results.length - committedCount -
      replayCount - conflictCount - accountRequiredCount;
}

class PrivateCloudInvoiceDraftPromotionService {
  PrivateCloudInvoiceDraftPromotionService({
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

  Future<List<AccountRecord>> listActiveAccounts() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'accounts',
      where: 'is_archived = 0',
      orderBy: 'sort_order ASC, name ASC, suffix ASC',
    );
    return rows.map(AccountRecord.fromMap).toList(growable: false);
  }

  Future<List<PrivateCloudInvoiceDraftCandidate>> listPendingDrafts() async {
    final db = await _databaseProvider();
    await createCanonicalProductionV16Tables(db);
    final rows = await db.rawQuery('''
      SELECT d.*
      FROM cloud_invoice_drafts d
      LEFT JOIN cloud_invoice_draft_promotions p ON p.draft_id = d.id
      LEFT JOIN cloud_invoice_operations r
        ON r.draft_id = d.id
       AND r.status = 'committed'
       AND r.operation_key LIKE 'cloud-invoice-conflict:%'
      WHERE p.draft_id IS NULL
        AND r.operation_key IS NULL
      ORDER BY d.invoice_date DESC, d.created_at DESC
    ''');
    final drafts = rows.map(_draftFromRow).toList(growable: false);
    final suggestions =
        await const OfficialInvoiceCategorySuggestionService().suggestMany(
      db,
      drafts
          .map(
            (draft) => OfficialInvoiceCategorySuggestionInput(
              id: draft.id,
              invoiceDate: draft.invoiceDate,
              sellerIdentifier: draft.sellerIdentifier,
              sellerName: draft.sellerName,
              lineItems: draft.lineItems,
            ),
          )
          .toList(growable: false),
    );
    return drafts
        .map(
          (draft) => draft.copyWith(
            categorySuggestion: suggestions[draft.id],
          ),
        )
        .toList(growable: false);
  }

  Future<PrivateCloudInvoiceDraftPromotionSummary> promoteMany({
    required List<PrivateCloudInvoiceDraftPromotionDecision> decisions,
    required bool finalConfirmation,
  }) async {
    if (!finalConfirmation) {
      throw StateError('DRAFT_PROMOTION_CONFIRMATION_REQUIRED');
    }
    if (decisions.isEmpty) {
      throw StateError('NO_DRAFT_SELECTED');
    }

    final results = <PrivateCloudInvoiceDraftPromotionResult>[];
    for (final decision in decisions) {
      results.add(await promote(decision: decision, finalConfirmation: true));
    }
    final summary = PrivateCloudInvoiceDraftPromotionSummary(
      results: List.unmodifiable(results),
    );
    if (summary.committedCount > 0) {
      _onLedgerChanged();
    }
    return summary;
  }

  Future<PrivateCloudInvoiceDraftPromotionResult> promote({
    required PrivateCloudInvoiceDraftPromotionDecision decision,
    required bool finalConfirmation,
  }) async {
    if (!finalConfirmation) {
      throw StateError('DRAFT_PROMOTION_CONFIRMATION_REQUIRED');
    }
    if (!decision.isComplete) {
      return PrivateCloudInvoiceDraftPromotionResult(
        draftId: decision.draftId,
        status: PrivateCloudInvoiceDraftPromotionStatus.rejected,
        message: 'REVIEW_FIELDS_REQUIRED',
      );
    }

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
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.replay,
          message: 'DRAFT_ALREADY_PROMOTED',
          transactionId: existingPromotion.single['transaction_id'] as String,
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
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.replay,
          message: 'DRAFT_ALREADY_RESOLVED',
          transactionId: existingResolution.single['transaction_id'] as String?,
        );
      }

      final draftRows = await transaction.query(
        'cloud_invoice_drafts',
        where: 'id = ?',
        whereArgs: <Object?>[decision.draftId],
        limit: 1,
      );
      if (draftRows.isEmpty) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.rejected,
          message: 'DRAFT_NOT_FOUND',
        );
      }
      final draft = _draftFromRow(draftRows.single);

      final normalizedInvoice = _normalizedInvoiceNumber(draft.invoiceNumber);
      final sameInvoiceLinks = await transaction.query(
        'cloud_invoice_metadata_links',
        columns: const <String>['transaction_id'],
        where: 'UPPER(invoice_number) = ?',
        whereArgs: <Object?>[normalizedInvoice],
        limit: 1,
      );
      if (sameInvoiceLinks.isNotEmpty) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.rejected,
          message: 'INVOICE_ALREADY_LINKED_TO_TRANSACTION',
          transactionId: sameInvoiceLinks.single['transaction_id'] as String?,
        );
      }

      final requestedAccountId = decision.accountId?.trim() ?? '';
      final candidateAccountId = requestedAccountId.isNotEmpty
          ? requestedAccountId
          : draft.accountId.trim();
      AccountRecord? reviewedAccount;
      if (candidateAccountId.isNotEmpty) {
        final candidateAccountRows = await transaction.query(
          'accounts',
          where: 'id = ? AND is_archived = 0',
          whereArgs: <Object?>[candidateAccountId],
          limit: 1,
        );
        if (candidateAccountRows.isEmpty && requestedAccountId.isNotEmpty) {
          return PrivateCloudInvoiceDraftPromotionResult(
            draftId: decision.draftId,
            status: PrivateCloudInvoiceDraftPromotionStatus.accountRequired,
            message: 'ACCOUNT_NOT_AVAILABLE_FOR_NEW_TRANSACTION',
          );
        }
        if (candidateAccountRows.isNotEmpty) {
          reviewedAccount = AccountRecord.fromMap(candidateAccountRows.single);
        }
      }
      if (requestedAccountId.isNotEmpty && reviewedAccount != null) {
        await transaction.update(
          'cloud_invoice_drafts',
          <String, Object?>{
            'account_id': reviewedAccount.id,
            'account_name': reviewedAccount.displayName,
            'account_resolution_status': 'selected',
          },
          where: 'id = ?',
          whereArgs: <Object?>[draft.id],
        );
      }

      final sourceCurrency = currencyFromCode(draft.currencyCode);
      final targetCurrency = reviewedAccount?.currency ?? CurrencyCode.twd;
      final sourceRateToTwd = sourceCurrency == CurrencyCode.twd
          ? 1.0
          : decision.exchangeRateToBase;
      final accountRateToTwd = targetCurrency == CurrencyCode.twd
          ? 1.0
          : decision.accountRateToBase;
      final crossRate = sourceCurrency == targetCurrency
          ? 1.0
          : decision.exchangeRateSourceToAccount ??
              ((sourceRateToTwd != null && accountRateToTwd != null)
                  ? sourceRateToTwd / accountRateToTwd
                  : null);
      final reviewedAccountAmount = decision.reviewedAccountAmount;
      if (reviewedAccountAmount != null &&
          (!reviewedAccountAmount.isFinite || reviewedAccountAmount <= 0)) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.rejected,
          message: 'FX_REVIEWED_ACCOUNT_AMOUNT_INVALID',
        );
      }
      if (sourceRateToTwd == null ||
          !sourceRateToTwd.isFinite ||
          sourceRateToTwd <= 0 ||
          accountRateToTwd == null ||
          !accountRateToTwd.isFinite ||
          accountRateToTwd <= 0 ||
          crossRate == null ||
          !crossRate.isFinite ||
          crossRate <= 0) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.rejected,
          message: 'FOREIGN_EXCHANGE_RATE_REQUIRED',
        );
      }
      final draftBaseAmount = draft.amount * sourceRateToTwd;

      final start = DateTime(
        draft.invoiceDate.year,
        draft.invoiceDate.month,
        draft.invoiceDate.day,
      );
      final end = start.add(const Duration(days: 1));
      final duplicates = await transaction.rawQuery(
        '''
        SELECT t.id
        FROM transactions t
        WHERE t.type = ?
          AND t.occurred_at >= ?
          AND t.occurred_at < ?
          AND (
            CASE
              WHEN COALESCE(t.base_amount, 0) = 0 THEN
                t.amount * CASE
                  WHEN COALESCE(t.exchange_rate_to_base, 0) = 0 THEN 1
                  ELSE t.exchange_rate_to_base
                END
              ELSE t.base_amount
            END
          ) BETWEEN ? AND ?
          AND NOT EXISTS (
            SELECT 1
            FROM cloud_invoice_metadata_links m
            WHERE m.transaction_id = t.id
          )
        ORDER BY t.occurred_at ASC, t.id ASC
        ''',
        <Object?>[
          TransactionType.expense.name,
          start.toIso8601String(),
          end.toIso8601String(),
          draftBaseAmount - 0.01,
          draftBaseAmount + 0.01,
        ],
      );
      final duplicateIds = duplicates
          .map((row) => row['id'] as String)
          .toList(growable: false);

      if (duplicateIds.length > 1) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.conflict,
          message: 'MULTIPLE_POTENTIAL_DUPLICATES_REVIEW_REQUIRED',
          candidateTransactionIds: List.unmodifiable(duplicateIds),
        );
      }
      if (duplicateIds.length == 1) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.conflict,
          message: 'POTENTIAL_DUPLICATE_REVIEW_REQUIRED',
          transactionId: duplicateIds.single,
          candidateTransactionIds: List.unmodifiable(duplicateIds),
        );
      }

      final resolvedAccountId = requestedAccountId.isNotEmpty
          ? requestedAccountId
          : draft.accountId.trim();
      if (resolvedAccountId.isEmpty) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.accountRequired,
          message: 'ACCOUNT_REQUIRED_FOR_NEW_TRANSACTION',
        );
      }
      final accountRows = await transaction.query(
        'accounts',
        where: 'id = ? AND is_archived = 0',
        whereArgs: <Object?>[resolvedAccountId],
        limit: 1,
      );
      if (accountRows.isEmpty) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.accountRequired,
          message: 'ACCOUNT_NOT_AVAILABLE_FOR_NEW_TRANSACTION',
        );
      }
      final account =
          reviewedAccount ?? AccountRecord.fromMap(accountRows.single);
      final resolvedDraft = draft.copyWith(
        accountId: account.id,
        accountName: account.displayName,
        accountResolutionStatus: 'selected',
      );
      await transaction.update(
        'cloud_invoice_drafts',
        <String, Object?>{
          'account_id': account.id,
          'account_name': account.displayName,
          'account_resolution_status': 'selected',
        },
        where: 'id = ?',
        whereArgs: <Object?>[draft.id],
      );

      if (account.currency != targetCurrency) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.rejected,
          message: 'FX_ACCOUNT_CURRENCY_CHANGED_REVIEW_REQUIRED',
        );
      }
      final currency = account.currency;
      final convertedAccountAmount =
          currency.roundAmount(draft.amount * crossRate);
      final accountAmount = reviewedAccountAmount == null
          ? convertedAccountAmount
          : currency.roundAmount(reviewedAccountAmount);
      final amountTolerance = currency.decimalDigits == 0 ? 0.5 : 0.005;
      if (reviewedAccountAmount != null &&
          (accountAmount - convertedAccountAmount).abs() > amountTolerance) {
        return PrivateCloudInvoiceDraftPromotionResult(
          draftId: decision.draftId,
          status: PrivateCloudInvoiceDraftPromotionStatus.rejected,
          message: 'FX_REVIEWED_ACCOUNT_AMOUNT_MISMATCH',
        );
      }
      final transactionId = _uuid.v4();
      final promotionKey = 'cloud-invoice-draft-promotion:${draft.id}';
      final noteParts = <String>[
        '發票：${draft.invoiceNumber}',
        '原始金額：${sourceCurrency.code} ${draft.amount}',
        '換算：1 ${sourceCurrency.code} = $crossRate ${currency.code}',
      ];
      if (reviewedAccountAmount != null) {
        noteParts.add(
          '實際扣帳金額：${currency.code} '
          '${accountAmount.toStringAsFixed(currency.decimalDigits)}',
        );
      }
      final sourceName = decision.fxSourceName?.trim() ?? '';
      if (sourceName.isNotEmpty) noteParts.add('匯率來源：$sourceName');
      if (decision.fxRequestedDate != null) {
        noteParts.add(
          '交易日：${decision.fxRequestedDate!.toIso8601String().split('T').first}',
        );
        noteParts.add(
          '交易時間：${decision.fxRequestedDate!.toIso8601String()}',
        );
      }
      if (decision.fxEffectiveDate != null) {
        noteParts.add(
          '匯率日期：${decision.fxEffectiveDate!.toIso8601String().split('T').first}',
        );
      }
      if (decision.fxEffectiveDateTime != null) {
        noteParts.add(
          '臺銀牌告時間：${decision.fxEffectiveDateTime!.toIso8601String()}',
        );
      }
      if (decision.fxSpotBuyToBase != null &&
          decision.fxSpotSellToBase != null) {
        noteParts.add(
          '臺銀即期買入：${decision.fxSpotBuyToBase}',
        );
        noteParts.add(
          '臺銀即期賣出：${decision.fxSpotSellToBase}',
        );
      }
      final selectionPolicy = decision.fxSelectionPolicy?.trim() ?? '';
      if (selectionPolicy.isNotEmpty) {
        noteParts.add('匯率選取規則：$selectionPolicy');
      }
      final sourceReference = decision.fxSourceReference?.trim() ?? '';
      if (sourceReference.isNotEmpty) {
        noteParts.add('匯率參考：$sourceReference');
      }
      final customNote = decision.note.trim();
      if (customNote.isNotEmpty) {
        noteParts.add(customNote);
      }
      final record = TransactionRecord(
        id: transactionId,
        type: TransactionType.expense,
        amount: accountAmount,
        category: decision.category.trim(),
        occurredAt: draft.invoiceDate,
        accountName: account.displayName,
        memberName: decision.memberName.trim(),
        merchantName: draft.sellerName.trim().isEmpty
            ? '未提供商家'
            : draft.sellerName.trim(),
        tagName: decision.tagName.trim(),
        note: noteParts.join('｜'),
        currency: currency,
        exchangeRateToBase: accountRateToTwd,
      );
      final now = _clock().toUtc();

      await transaction.insert(
        'transactions',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await transaction.insert(
        'cloud_invoice_metadata_links',
        <String, Object?>{
          'id': _uuid.v4(),
          'operation_key': promotionKey,
          'transaction_id': transactionId,
          'candidate_reference': draft.candidateReference,
          'invoice_number': draft.invoiceNumber,
          'seller_identifier': draft.sellerIdentifier,
          'seller_name': draft.sellerName,
          'invoice_date': draft.invoiceDate.toIso8601String(),
          'time_precision': draft.timePrecision.name,
          'time_source': draft.timeSource.name,
          'currency_code': sourceCurrency.code,
          'currency_source': draft.currencySource.name,
          'tax_amount': draft.taxAmount,
          'merchant_id': null,
          'line_items_json': encodeCloudInvoiceLineItems(draft.lineItems),
          'payload_version': canonicalCloudInvoicePayloadVersion,
          'created_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await transaction.insert(
        'cloud_invoice_draft_promotions',
        <String, Object?>{
          'draft_id': draft.id,
          'promotion_key': promotionKey,
          'draft_operation_key': draft.operationKey,
          'draft_fingerprint': resolvedDraft.fingerprint,
          'transaction_id': transactionId,
          'category': decision.category.trim(),
          'member_name': decision.memberName.trim(),
          'tag_name': decision.tagName.trim(),
          'note': customNote,
          'created_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return PrivateCloudInvoiceDraftPromotionResult(
        draftId: draft.id,
        status: PrivateCloudInvoiceDraftPromotionStatus.committed,
        message: 'DRAFT_PROMOTED',
        transactionId: transactionId,
      );
    });
  }

  PrivateCloudInvoiceDraftCandidate _draftFromRow(Map<String, Object?> row) {
    final payloadVersion = (row['payload_version'] as num?)?.toInt();
    if (payloadVersion != canonicalCloudInvoicePayloadVersion) {
      throw FormatException(
        'DRAFT_PAYLOAD_VERSION_UNSUPPORTED:$payloadVersion',
      );
    }
    return PrivateCloudInvoiceDraftCandidate(
      id: row['id'] as String,
      operationKey: row['operation_key'] as String,
      candidateReference: row['candidate_reference'] as String,
      accountId: row['account_id'] as String,
      accountName: row['account_name'] as String,
      accountResolutionStatus:
          row['account_resolution_status'] as String? ?? 'selected',
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
      lineItems: decodeCloudInvoiceLineItems(row['line_items_json'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

String _normalizedInvoiceNumber(String value) => value.trim().toUpperCase();
