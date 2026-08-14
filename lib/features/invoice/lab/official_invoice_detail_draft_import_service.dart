import 'package:sqflite/sqflite.dart';

import '../../../database/production_database_coordinator.dart';
import '../../../database/production_schema_v16.dart';
import '../../account/account_record.dart';
import '../cloud_invoice_candidate.dart';
import 'canonical_cloud_invoice_persistence_service.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_reconciliation_models.dart';
import 'cloud_invoice_reconciliation_review_decision.dart';
import 'official_invoice_detail_enrichment.dart';

bool isOfficialInvoiceDetailEligibleForFormalImport(
  OfficialInvoiceDetailEnrichment item,
) {
  return item.success &&
      item.invoiceIdentityMatches &&
      item.hasUsableItemRows &&
      item.detailTotalMatchesCsv &&
      item.sellerIdentifierConsistent &&
      item.exactTimestamp != null &&
      item.detailTotal != null &&
      item.detailTotal! > 0 &&
      item.lineItems.isNotEmpty;
}

enum OfficialInvoiceDetailDraftImportStatus {
  staged,
  replay,
  alreadyFormal,
  conflict,
  rejected,
}

class OfficialInvoiceDetailDraftImportResult {
  const OfficialInvoiceDetailDraftImportResult({
    required this.invoiceNumber,
    required this.status,
    required this.message,
    this.draftId,
    this.transactionId,
  });

  final String invoiceNumber;
  final OfficialInvoiceDetailDraftImportStatus status;
  final String message;
  final String? draftId;
  final String? transactionId;

  bool get hasPendingDraft =>
      draftId != null &&
      (status == OfficialInvoiceDetailDraftImportStatus.staged ||
          status == OfficialInvoiceDetailDraftImportStatus.replay);
}

class OfficialInvoiceDetailDraftImportSummary {
  const OfficialInvoiceDetailDraftImportSummary({
    required this.results,
    required this.transactionCountUnchanged,
  });

  final List<OfficialInvoiceDetailDraftImportResult> results;
  final bool transactionCountUnchanged;

  int get stagedCount => results
      .where(
        (item) => item.status == OfficialInvoiceDetailDraftImportStatus.staged,
      )
      .length;

  int get replayCount => results
      .where(
        (item) => item.status == OfficialInvoiceDetailDraftImportStatus.replay,
      )
      .length;

  int get alreadyFormalCount => results
      .where(
        (item) =>
            item.status == OfficialInvoiceDetailDraftImportStatus.alreadyFormal,
      )
      .length;

  int get conflictCount => results
      .where(
        (item) => item.status == OfficialInvoiceDetailDraftImportStatus.conflict,
      )
      .length;

  int get rejectedCount => results.length -
      stagedCount -
      replayCount -
      alreadyFormalCount -
      conflictCount;

  Set<String> get pendingDraftIds => results
      .where((item) => item.hasPendingDraft)
      .map((item) => item.draftId!)
      .toSet();
}

abstract interface class OfficialInvoiceDetailDraftImportPort {
  Future<List<AccountRecord>> listActiveAccounts();

  Future<OfficialInvoiceDetailDraftImportSummary> stageDrafts({
    required OfficialInvoiceDetailBatchResult batchResult,
    required Set<String> invoiceNumbers,
    required AccountRecord? account,
    required bool finalConfirmation,
  });
}

class OfficialInvoiceDetailDraftImportService
    implements OfficialInvoiceDetailDraftImportPort {
  OfficialInvoiceDetailDraftImportService({
    Future<Database> Function()? databaseProvider,
    CanonicalCloudInvoicePersistenceService? persistenceService,
    DateTime Function()? clock,
  })  : _databaseProvider = databaseProvider ??
            (() => ProductionDatabaseCoordinator.instance.database),
        _persistenceService = persistenceService ??
            CanonicalCloudInvoicePersistenceService(
              databaseProvider: databaseProvider ??
                  (() => ProductionDatabaseCoordinator.instance.database),
            ),
        _clock = clock ?? DateTime.now;

  final Future<Database> Function() _databaseProvider;
  final CanonicalCloudInvoicePersistenceService _persistenceService;
  final DateTime Function() _clock;

  @override
  Future<List<AccountRecord>> listActiveAccounts() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'accounts',
      where: 'is_archived = 0',
      orderBy: 'sort_order ASC, name ASC, suffix ASC',
    );
    return rows.map(AccountRecord.fromMap).toList(growable: false);
  }

  @override
  Future<OfficialInvoiceDetailDraftImportSummary> stageDrafts({
    required OfficialInvoiceDetailBatchResult batchResult,
    required Set<String> invoiceNumbers,
    required AccountRecord? account,
    required bool finalConfirmation,
  }) async {
    if (!finalConfirmation) {
      throw StateError('OFFICIAL_DETAIL_DRAFT_CONFIRMATION_REQUIRED');
    }
    if (invoiceNumbers.isEmpty) {
      throw StateError('NO_OFFICIAL_DETAIL_SELECTED');
    }

    final selected = invoiceNumbers
        .map(_normalizeInvoiceNumber)
        .where((value) => value.isNotEmpty)
        .toSet();
    final byInvoice = <String, OfficialInvoiceDetailEnrichment>{
      for (final item in batchResult.results)
        _normalizedItemInvoiceNumber(item): item,
    };
    final db = await _databaseProvider();
    await createCanonicalProductionV16Tables(db);
    final before = await _countTransactions(db);
    final results = <OfficialInvoiceDetailDraftImportResult>[];

    for (final invoiceNumber in selected) {
      final item = byInvoice[invoiceNumber];
      if (item == null) {
        results.add(
          OfficialInvoiceDetailDraftImportResult(
            invoiceNumber: invoiceNumber,
            status: OfficialInvoiceDetailDraftImportStatus.rejected,
            message: 'OFFICIAL_DETAIL_RESULT_NOT_FOUND',
          ),
        );
        continue;
      }
      if (!isOfficialInvoiceDetailEligibleForFormalImport(item)) {
        results.add(
          OfficialInvoiceDetailDraftImportResult(
            invoiceNumber: invoiceNumber,
            status: OfficialInvoiceDetailDraftImportStatus.rejected,
            message: 'OFFICIAL_DETAIL_NOT_ELIGIBLE',
          ),
        );
        continue;
      }

      final pendingDraft = await db.rawQuery(
        '''
        SELECT d.id
        FROM cloud_invoice_drafts d
        LEFT JOIN cloud_invoice_draft_promotions p ON p.draft_id = d.id
        WHERE UPPER(d.invoice_number) = ?
          AND p.draft_id IS NULL
        ORDER BY d.created_at DESC
        LIMIT 1
        ''',
        <Object?>[invoiceNumber],
      );
      if (pendingDraft.isNotEmpty) {
        results.add(
          OfficialInvoiceDetailDraftImportResult(
            invoiceNumber: invoiceNumber,
            status: OfficialInvoiceDetailDraftImportStatus.replay,
            message: 'OFFICIAL_INVOICE_DRAFT_ALREADY_PENDING',
            draftId: pendingDraft.single['id'] as String,
          ),
        );
        continue;
      }

      final formalIdentity = await _inspectExistingFormalIdentity(db, item);
      if (formalIdentity.isExactMatch) {
        results.add(
          OfficialInvoiceDetailDraftImportResult(
            invoiceNumber: invoiceNumber,
            status: OfficialInvoiceDetailDraftImportStatus.alreadyFormal,
            message: 'OFFICIAL_INVOICE_ALREADY_FORMAL',
            transactionId: formalIdentity.transactionId,
          ),
        );
        continue;
      }
      if (formalIdentity.hasConflict) {
        results.add(
          OfficialInvoiceDetailDraftImportResult(
            invoiceNumber: invoiceNumber,
            status: OfficialInvoiceDetailDraftImportStatus.conflict,
            message: 'OFFICIAL_INVOICE_IDENTITY_CONFLICT',
            transactionId: formalIdentity.transactionId,
          ),
        );
        continue;
      }

      final request = buildDraftRequest(account, item);
      final persistenceResult = await _persistenceService.execute(request);
      results.add(
        _mapPersistenceResult(
          invoiceNumber,
          persistenceResult,
        ),
      );
    }

    final after = await _countTransactions(db);
    return OfficialInvoiceDetailDraftImportSummary(
      results: List.unmodifiable(results),
      transactionCountUnchanged: before == after,
    );
  }

  CloudInvoicePersistenceRequest buildDraftRequest(
    AccountRecord? account,
    OfficialInvoiceDetailEnrichment item,
  ) {
    if (!isOfficialInvoiceDetailEligibleForFormalImport(item)) {
      throw StateError('OFFICIAL_DETAIL_NOT_ELIGIBLE');
    }
    final candidate = _candidateFromEnrichment(item);
    final currencyCode = _normalizedCurrencyCode(item.currencyCode);
    final now = _clock().toUtc();
    return CloudInvoicePersistenceRequest(
      facts: CloudInvoiceCandidateFacts(
        candidate: candidate,
        timePrecision: CloudInvoiceTimePrecision.exactDateTime,
        timeSource: CloudInvoiceTimeSource.officialDetailPage,
        currencyCode: currencyCode,
        currencySource: currencyCode == null
            ? CloudInvoiceCurrencySource.unknown
            : CloudInvoiceCurrencySource.officialDetailPage,
      ),
      decision: CloudInvoiceReconciliationReviewDecision(
        action: CloudInvoiceReconciliationOutcome.createNewDraft,
        selectedTransactionId: null,
        selectedAccountId: account?.id,
        merchantProposalReviewed: true,
        merchantProposalConfirmed: false,
        replacementSecondConfirmationCompleted: false,
        candidateReference: candidate.duplicateKey,
        decidedAt: now,
      ),
      expectedAccountFingerprint:
          account == null ? null : accountFingerprint(account),
      requestedAt: now,
    );
  }

  CloudInvoiceCandidate _candidateFromEnrichment(
    OfficialInvoiceDetailEnrichment item,
  ) {
    final sellerName = item.sellerName?.trim() ?? '';
    final warnings = <CloudInvoiceCandidateWarning>[
      if (sellerName.isEmpty) CloudInvoiceCandidateWarning.missingSellerName,
      if (item.officialTaxLabel == '推算稅額（使用者確認）' ||
          item.lineItemsTruncated)
        CloudInvoiceCandidateWarning.partialPayload,
    ];
    return CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.confirmedDraft,
      invoiceNumber: _normalizedItemInvoiceNumber(item),
      invoiceDate: item.exactTimestamp!,
      sellerIdentifier: item.sellerIdentifier?.trim() ?? '',
      sellerName: sellerName,
      totalAmount: item.detailTotal!,
      carrierType: 'official-webview',
      carrierMaskedId: '****',
      fetchedAt: item.fetchedAt,
      taxAmount: item.officialTaxAmount,
      lineItems: item.lineItems
          .map((lineItem) => lineItem.toCandidateItem())
          .toList(growable: false),
      warnings: warnings,
    );
  }

  OfficialInvoiceDetailDraftImportResult _mapPersistenceResult(
    String invoiceNumber,
    CloudInvoicePersistenceResult result,
  ) {
    return switch (result.status) {
      CloudInvoicePersistenceStatus.committed =>
        OfficialInvoiceDetailDraftImportResult(
          invoiceNumber: invoiceNumber,
          status: OfficialInvoiceDetailDraftImportStatus.staged,
          message: result.message,
          draftId: result.draftId,
        ),
      CloudInvoicePersistenceStatus.alreadyApplied =>
        OfficialInvoiceDetailDraftImportResult(
          invoiceNumber: invoiceNumber,
          status: OfficialInvoiceDetailDraftImportStatus.replay,
          message: result.message,
          draftId: result.draftId,
          transactionId: result.transactionId,
        ),
      CloudInvoicePersistenceStatus.conflict =>
        OfficialInvoiceDetailDraftImportResult(
          invoiceNumber: invoiceNumber,
          status: OfficialInvoiceDetailDraftImportStatus.conflict,
          message: result.message,
          draftId: result.draftId,
          transactionId: result.transactionId,
        ),
      _ => OfficialInvoiceDetailDraftImportResult(
          invoiceNumber: invoiceNumber,
          status: OfficialInvoiceDetailDraftImportStatus.rejected,
          message: result.message,
          draftId: result.draftId,
          transactionId: result.transactionId,
        ),
    };
  }

  Future<_ExistingFormalIdentity> _inspectExistingFormalIdentity(
    DatabaseExecutor db,
    OfficialInvoiceDetailEnrichment item,
  ) async {
    final timestamp = item.exactTimestamp;
    if (timestamp == null) {
      return const _ExistingFormalIdentity();
    }
    final rows = await db.query(
      'cloud_invoice_metadata_links',
      columns: const <String>['transaction_id', 'invoice_date'],
      where: 'UPPER(invoice_number) = ?',
      whereArgs: <Object?>[_normalizedItemInvoiceNumber(item)],
      orderBy: 'created_at DESC',
    );
    if (rows.isEmpty) return const _ExistingFormalIdentity();

    final exactTransactionIds = <String>{};
    var hasDifferentTimestamp = false;
    for (final row in rows) {
      final linkedTimestamp =
          DateTime.tryParse(row['invoice_date'] as String? ?? '');
      final transactionId = row['transaction_id'] as String?;
      if (linkedTimestamp != null &&
          transactionId != null &&
          _sameExactTimestamp(linkedTimestamp, timestamp)) {
        exactTransactionIds.add(transactionId);
      } else {
        hasDifferentTimestamp = true;
      }
    }
    if (!hasDifferentTimestamp && exactTransactionIds.length == 1) {
      return _ExistingFormalIdentity(
        transactionId: exactTransactionIds.single,
        isExactMatch: true,
      );
    }
    return _ExistingFormalIdentity(
      transactionId:
          exactTransactionIds.length == 1 ? exactTransactionIds.single : null,
      hasConflict: true,
    );
  }

  Future<int> _countTransactions(DatabaseExecutor db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM transactions');
    return (rows.single['total'] as num).toInt();
  }
}

String _normalizedItemInvoiceNumber(OfficialInvoiceDetailEnrichment item) {
  final value = item.invoiceNumber.trim().isNotEmpty
      ? item.invoiceNumber
      : item.requestedInvoiceNumber;
  return _normalizeInvoiceNumber(value);
}

String _normalizeInvoiceNumber(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

String? _normalizedCurrencyCode(String? value) {
  final normalized = value?.trim().toUpperCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

class _ExistingFormalIdentity {
  const _ExistingFormalIdentity({
    this.transactionId,
    this.isExactMatch = false,
    this.hasConflict = false,
  });

  final String? transactionId;
  final bool isExactMatch;
  final bool hasConflict;
}

bool _sameExactTimestamp(DateTime left, DateTime right) {
  if (left.isAtSameMomentAs(right)) return true;
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day &&
      left.hour == right.hour &&
      left.minute == right.minute &&
      left.second == right.second;
}
