import 'package:sqflite/sqflite.dart';

import '../../../database/production_database_coordinator.dart';
import '../../../database/production_schema_v16.dart';
import '../../account/account_record.dart';
import 'canonical_cloud_invoice_persistence_codec.dart';
import 'official_invoice_detail_draft_import_service.dart';
import 'official_invoice_detail_enrichment.dart';

enum OfficialInvoiceDetailImportPreflightStatus {
  selectable,
  rebuildableDeleted,
  alreadyFormal,
  identityConflict,
  validationRejected,
}

class OfficialInvoiceDetailImportPreflightItem {
  const OfficialInvoiceDetailImportPreflightItem({
    required this.enrichment,
    required this.status,
    this.transactionId,
    this.message,
  });

  final OfficialInvoiceDetailEnrichment enrichment;
  final OfficialInvoiceDetailImportPreflightStatus status;
  final String? transactionId;
  final String? message;

  String get invoiceNumber => normalizedOfficialInvoiceNumber(enrichment);
  bool get isSelectable =>
      status == OfficialInvoiceDetailImportPreflightStatus.selectable ||
      status == OfficialInvoiceDetailImportPreflightStatus.rebuildableDeleted;
  bool get isDeletedFormalRebuild =>
      status == OfficialInvoiceDetailImportPreflightStatus.rebuildableDeleted;
  bool get requiresEstimatedTaxConfirmation =>
      isSelectable && enrichment.canUseUserConfirmedEstimatedTax;
}

class OfficialInvoiceDetailImportPreflightSnapshot {
  const OfficialInvoiceDetailImportPreflightSnapshot({
    required this.accounts,
    required this.items,
  });

  final List<AccountRecord> accounts;
  final List<OfficialInvoiceDetailImportPreflightItem> items;

  List<OfficialInvoiceDetailImportPreflightItem> get selectableItems =>
      items.where((item) => item.isSelectable).toList(growable: false);

  List<OfficialInvoiceDetailImportPreflightItem> get rebuildableDeletedItems =>
      items
          .where(
            (item) =>
                item.status ==
                OfficialInvoiceDetailImportPreflightStatus.rebuildableDeleted,
          )
          .toList(growable: false);

  List<OfficialInvoiceDetailImportPreflightItem> get alreadyFormalItems => items
      .where(
        (item) =>
            item.status ==
            OfficialInvoiceDetailImportPreflightStatus.alreadyFormal,
      )
      .toList(growable: false);

  List<OfficialInvoiceDetailImportPreflightItem> get conflictItems => items
      .where(
        (item) =>
            item.status ==
            OfficialInvoiceDetailImportPreflightStatus.identityConflict,
      )
      .toList(growable: false);

  List<OfficialInvoiceDetailImportPreflightItem> get rejectedItems => items
      .where(
        (item) =>
            item.status ==
            OfficialInvoiceDetailImportPreflightStatus.validationRejected,
      )
      .toList(growable: false);
}

bool isOfficialInvoiceDetailEligibleForFormalImportV2(
  OfficialInvoiceDetailEnrichment item,
) {
  if (isOfficialInvoiceDetailEligibleForFormalImport(item)) return true;
  return item.invoiceIdentityMatches &&
      item.detailTotalMatchesCsv &&
      item.sellerIdentifierConsistent &&
      item.exactTimestamp != null &&
      item.detailTotal != null &&
      item.detailTotal! > 0 &&
      item.lineItems.isNotEmpty &&
      item.canUseUserConfirmedEstimatedTax;
}

OfficialInvoiceDetailEnrichment withUserConfirmedEstimatedTax(
  OfficialInvoiceDetailEnrichment item,
) {
  final estimatedTax = item.positiveEstimatedTaxAmount;
  if (estimatedTax == null || !item.canUseUserConfirmedEstimatedTax) {
    throw StateError('ESTIMATED_TAX_NOT_AVAILABLE');
  }
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: item.requestedInvoiceNumber,
    invoiceNumber: item.invoiceNumber,
    selectorProfileVersion: item.selectorProfileVersion,
    fetchedAt: item.fetchedAt,
    success: true,
    invoiceIdentityMatches: item.invoiceIdentityMatches,
    detailTotalInternallyConsistent: true,
    detailTotalMatchesCsv: item.detailTotalMatchesCsv,
    sellerIdentifierConsistent: item.sellerIdentifierConsistent,
    lineItems: List<OfficialInvoiceDetailLineItem>.unmodifiable(
      <OfficialInvoiceDetailLineItem>[
        ...item.lineItems,
        OfficialInvoiceDetailLineItem(
          name: '推算稅額（使用者確認）',
          quantity: 1,
          unitPrice: estimatedTax,
          amount: estimatedTax,
        ),
      ],
    ),
    exactTimestamp: item.exactTimestamp,
    currencyCode: item.currencyCode,
    officialStatus: item.officialStatus,
    sellerIdentifier: item.sellerIdentifier,
    sellerName: item.sellerName,
    expectedTotal: item.expectedTotal,
    detailTotal: item.detailTotal,
    officialTaxAmount: estimatedTax,
    officialTaxLabel: '推算稅額（使用者確認）',
    lineItemSubtotal: item.lineItemSubtotal,
    unallocatedDifference: 0,
    errorCode: null,
    warningCode: item.warningCode,
    declaredItemCount: item.declaredItemCount,
    omittedItemCount: item.omittedItemCount,
    lineItemsTruncated: item.lineItemsTruncated,
    dialogDetected: item.dialogDetected,
    summaryTableDetected: item.summaryTableDetected,
    itemTableDetected: item.itemTableDetected,
    detectedItemRowCount: item.detectedItemRowCount,
  );
}

class OfficialInvoiceDetailDraftImportV2Service {
  OfficialInvoiceDetailDraftImportV2Service({
    Future<Database> Function()? databaseProvider,
    OfficialInvoiceDetailDraftImportService? baseService,
  }) : _databaseProvider =
           databaseProvider ??
           (() => ProductionDatabaseCoordinator.instance.database),
       _baseService =
           baseService ??
           OfficialInvoiceDetailDraftImportService(
             databaseProvider:
                 databaseProvider ??
                 (() => ProductionDatabaseCoordinator.instance.database),
           );

  final Future<Database> Function() _databaseProvider;
  final OfficialInvoiceDetailDraftImportService _baseService;

  Future<List<OfficialInvoiceDetailImportPreflightItem>> classifyItems(
    OfficialInvoiceDetailBatchResult batchResult,
  ) async {
    final db = await _databaseProvider();
    await createCanonicalProductionV16Tables(db);
    final items = <OfficialInvoiceDetailImportPreflightItem>[];
    for (final enrichment in batchResult.results) {
      if (!isOfficialInvoiceDetailEligibleForFormalImportV2(enrichment)) {
        items.add(
          OfficialInvoiceDetailImportPreflightItem(
            enrichment: enrichment,
            status:
                OfficialInvoiceDetailImportPreflightStatus.validationRejected,
            message: enrichment.errorCode ?? 'OFFICIAL_DETAIL_NOT_ELIGIBLE',
          ),
        );
        continue;
      }
      items.add(await _classifyFormalIdentity(db, enrichment));
    }
    return List<OfficialInvoiceDetailImportPreflightItem>.unmodifiable(items);
  }

  Future<OfficialInvoiceDetailImportPreflightSnapshot> loadPreflight(
    OfficialInvoiceDetailBatchResult batchResult,
  ) async {
    final accounts = await _baseService.listActiveAccounts();
    final items = await classifyItems(batchResult);
    return OfficialInvoiceDetailImportPreflightSnapshot(
      accounts: List<AccountRecord>.unmodifiable(accounts),
      items: items,
    );
  }

  Future<OfficialInvoiceDetailDraftImportSummary> stageDrafts({
    required OfficialInvoiceDetailBatchResult batchResult,
    required Set<String> invoiceNumbers,
    required Set<String> confirmedEstimatedTaxInvoiceNumbers,
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
        .map(normalizeInvoiceNumber)
        .where((value) => value.isNotEmpty)
        .toSet();
    final confirmedEstimates = confirmedEstimatedTaxInvoiceNumbers
        .map(normalizeInvoiceNumber)
        .where((value) => value.isNotEmpty)
        .toSet();
    final classifiedItems = await classifyItems(batchResult);
    final preflightByInvoice =
        <String, OfficialInvoiceDetailImportPreflightItem>{
          for (final item in classifiedItems) item.invoiceNumber: item,
        };
    final db = await _databaseProvider();
    await createCanonicalProductionV16Tables(db);

    final preResults = <OfficialInvoiceDetailDraftImportResult>[];
    final delegateInvoiceNumbers = <String>{};
    final replacements = <String, OfficialInvoiceDetailEnrichment>{};

    for (final invoiceNumber in selected) {
      final item = preflightByInvoice[invoiceNumber];
      if (item == null) {
        preResults.add(
          OfficialInvoiceDetailDraftImportResult(
            invoiceNumber: invoiceNumber,
            status: OfficialInvoiceDetailDraftImportStatus.rejected,
            message: 'OFFICIAL_DETAIL_RESULT_NOT_FOUND',
          ),
        );
        continue;
      }
      switch (item.status) {
        case OfficialInvoiceDetailImportPreflightStatus.alreadyFormal:
          preResults.add(
            OfficialInvoiceDetailDraftImportResult(
              invoiceNumber: invoiceNumber,
              status: OfficialInvoiceDetailDraftImportStatus.alreadyFormal,
              message: 'OFFICIAL_INVOICE_ALREADY_FORMAL',
              transactionId: item.transactionId,
            ),
          );
          continue;
        case OfficialInvoiceDetailImportPreflightStatus.identityConflict:
          preResults.add(
            OfficialInvoiceDetailDraftImportResult(
              invoiceNumber: invoiceNumber,
              status: OfficialInvoiceDetailDraftImportStatus.conflict,
              message: item.message ?? 'OFFICIAL_INVOICE_IDENTITY_CONFLICT',
              transactionId: item.transactionId,
            ),
          );
          continue;
        case OfficialInvoiceDetailImportPreflightStatus.validationRejected:
          preResults.add(
            OfficialInvoiceDetailDraftImportResult(
              invoiceNumber: invoiceNumber,
              status: OfficialInvoiceDetailDraftImportStatus.rejected,
              message: item.message ?? 'OFFICIAL_DETAIL_NOT_ELIGIBLE',
            ),
          );
          continue;
        case OfficialInvoiceDetailImportPreflightStatus.rebuildableDeleted:
        case OfficialInvoiceDetailImportPreflightStatus.selectable:
          break;
      }

      var effectiveEnrichment = item.enrichment;
      if (effectiveEnrichment.canUseUserConfirmedEstimatedTax) {
        if (!confirmedEstimates.contains(invoiceNumber)) {
          preResults.add(
            OfficialInvoiceDetailDraftImportResult(
              invoiceNumber: invoiceNumber,
              status: OfficialInvoiceDetailDraftImportStatus.rejected,
              message: 'ESTIMATED_TAX_CONFIRMATION_REQUIRED',
            ),
          );
          continue;
        }
        effectiveEnrichment = withUserConfirmedEstimatedTax(
          effectiveEnrichment,
        );
        replacements[invoiceNumber] = effectiveEnrichment;
      }
      if (item.status ==
          OfficialInvoiceDetailImportPreflightStatus.rebuildableDeleted) {
        await _reopenDeletedFormalInvoice(
          db,
          item,
          enrichment: effectiveEnrichment,
          account: account,
        );
      }
      delegateInvoiceNumbers.add(invoiceNumber);
    }

    if (delegateInvoiceNumbers.isEmpty) {
      return OfficialInvoiceDetailDraftImportSummary(
        results: List<OfficialInvoiceDetailDraftImportResult>.unmodifiable(
          preResults,
        ),
        transactionCountUnchanged: true,
      );
    }

    final transformedResults = batchResult.results
        .map((item) {
          return replacements[normalizedOfficialInvoiceNumber(item)] ?? item;
        })
        .toList(growable: false);
    final delegated = await _baseService.stageDrafts(
      batchResult: OfficialInvoiceDetailBatchResult(
        requestedCount: batchResult.requestedCount,
        results: transformedResults,
        cancelled: batchResult.cancelled,
        traces: batchResult.traces,
        errorCode: batchResult.errorCode,
      ),
      invoiceNumbers: delegateInvoiceNumbers,
      account: account,
      finalConfirmation: true,
    );
    return OfficialInvoiceDetailDraftImportSummary(
      results: List<OfficialInvoiceDetailDraftImportResult>.unmodifiable(
        <OfficialInvoiceDetailDraftImportResult>[
          ...preResults,
          ...delegated.results,
        ],
      ),
      transactionCountUnchanged: delegated.transactionCountUnchanged,
    );
  }

  Future<OfficialInvoiceDetailImportPreflightItem> _classifyFormalIdentity(
    DatabaseExecutor db,
    OfficialInvoiceDetailEnrichment enrichment,
  ) async {
    final officialTimestamp = enrichment.exactTimestamp;
    if (officialTimestamp == null) {
      return OfficialInvoiceDetailImportPreflightItem(
        enrichment: enrichment,
        status: OfficialInvoiceDetailImportPreflightStatus.validationRejected,
        message: 'DETAIL_TIMESTAMP_NOT_FOUND',
      );
    }
    final rows = await db.rawQuery(
      '''
      SELECT
        m.transaction_id,
        m.invoice_date,
        CASE WHEN t.id IS NULL THEN 0 ELSE 1 END AS transaction_exists
      FROM cloud_invoice_metadata_links m
      LEFT JOIN transactions t ON t.id = m.transaction_id
      WHERE UPPER(m.invoice_number) = ?
      ORDER BY m.created_at DESC
      ''',
      <Object?>[normalizedOfficialInvoiceNumber(enrichment)],
    );
    if (rows.isEmpty) {
      return OfficialInvoiceDetailImportPreflightItem(
        enrichment: enrichment,
        status: OfficialInvoiceDetailImportPreflightStatus.selectable,
      );
    }

    final activeExactTransactionIds = <String>{};
    var hasActiveDifferentTimestamp = false;
    final staleExactTransactionIds = <String>{};
    var hasStaleDifferentTimestamp = false;

    for (final row in rows) {
      final timestamp = DateTime.tryParse(row['invoice_date'] as String? ?? '');
      final transactionId = row['transaction_id'] as String?;
      final transactionExists =
          (row['transaction_exists'] as num?)?.toInt() == 1;
      final exact =
          timestamp != null &&
          transactionId != null &&
          _sameExactTimestamp(timestamp, officialTimestamp);
      if (transactionExists) {
        if (exact) {
          activeExactTransactionIds.add(transactionId);
        } else {
          hasActiveDifferentTimestamp = true;
        }
      } else {
        if (exact) {
          staleExactTransactionIds.add(transactionId);
        } else {
          hasStaleDifferentTimestamp = true;
        }
      }
    }

    if (activeExactTransactionIds.length == 1 && !hasActiveDifferentTimestamp) {
      return OfficialInvoiceDetailImportPreflightItem(
        enrichment: enrichment,
        status: OfficialInvoiceDetailImportPreflightStatus.alreadyFormal,
        transactionId: activeExactTransactionIds.single,
        message: 'OFFICIAL_INVOICE_ALREADY_FORMAL',
      );
    }
    if (activeExactTransactionIds.isNotEmpty || hasActiveDifferentTimestamp) {
      return OfficialInvoiceDetailImportPreflightItem(
        enrichment: enrichment,
        status: OfficialInvoiceDetailImportPreflightStatus.identityConflict,
        transactionId: activeExactTransactionIds.length == 1
            ? activeExactTransactionIds.single
            : null,
        message: 'OFFICIAL_INVOICE_IDENTITY_CONFLICT',
      );
    }
    if (staleExactTransactionIds.isNotEmpty && !hasStaleDifferentTimestamp) {
      return OfficialInvoiceDetailImportPreflightItem(
        enrichment: enrichment,
        status: OfficialInvoiceDetailImportPreflightStatus.rebuildableDeleted,
        transactionId: staleExactTransactionIds.length == 1
            ? staleExactTransactionIds.single
            : null,
        message: 'OFFICIAL_INVOICE_FORMAL_TRANSACTION_DELETED_REBUILD_ALLOWED',
      );
    }
    return OfficialInvoiceDetailImportPreflightItem(
      enrichment: enrichment,
      status: OfficialInvoiceDetailImportPreflightStatus.identityConflict,
      message: 'OFFICIAL_INVOICE_STALE_LINK_IDENTITY_CONFLICT',
    );
  }

  Future<void> _reopenDeletedFormalInvoice(
    Database db,
    OfficialInvoiceDetailImportPreflightItem item, {
    required OfficialInvoiceDetailEnrichment enrichment,
    required AccountRecord? account,
  }) async {
    final invoiceNumber = item.invoiceNumber;
    final officialTimestamp = enrichment.exactTimestamp;
    if (officialTimestamp == null) {
      throw StateError('DETAIL_TIMESTAMP_NOT_FOUND');
    }
    final refreshRequest = _baseService.buildDraftRequest(account, enrichment);
    final refreshCandidate = refreshRequest.facts.candidate;

    await db.transaction((transaction) async {
      final staleRows = await transaction.rawQuery(
        '''
        SELECT
          m.transaction_id,
          m.candidate_reference,
          m.invoice_date
        FROM cloud_invoice_metadata_links m
        LEFT JOIN transactions t ON t.id = m.transaction_id
        WHERE UPPER(m.invoice_number) = ?
          AND t.id IS NULL
        ORDER BY m.created_at DESC
        ''',
        <Object?>[invoiceNumber],
      );
      final exactRows = staleRows
          .where((row) {
            final timestamp = DateTime.tryParse(
              row['invoice_date'] as String? ?? '',
            );
            return timestamp != null &&
                _sameExactTimestamp(timestamp, officialTimestamp);
          })
          .toList(growable: false);
      if (exactRows.isEmpty) {
        throw StateError('DELETED_FORMAL_LINK_NOT_FOUND');
      }

      final staleTransactionIds = exactRows
          .map((row) => row['transaction_id'] as String?)
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toSet();
      final candidateReferences = exactRows
          .map((row) => row['candidate_reference'] as String?)
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toSet();
      for (final transactionId in staleTransactionIds) {
        await transaction.delete(
          'cloud_invoice_draft_promotions',
          where: 'transaction_id = ?',
          whereArgs: <Object?>[transactionId],
        );
        await transaction.delete(
          'cloud_invoice_metadata_links',
          where: 'transaction_id = ? AND UPPER(invoice_number) = ?',
          whereArgs: <Object?>[transactionId, invoiceNumber],
        );
      }

      final pendingRows = await transaction.rawQuery(
        '''
        SELECT d.id, d.candidate_reference, d.invoice_date
        FROM cloud_invoice_drafts d
        LEFT JOIN cloud_invoice_draft_promotions p ON p.draft_id = d.id
        WHERE UPPER(d.invoice_number) = ?
          AND p.draft_id IS NULL
        ORDER BY d.created_at DESC
        ''',
        <Object?>[invoiceNumber],
      );
      final exactPending = pendingRows
          .where((row) {
            final timestamp = DateTime.tryParse(
              row['invoice_date'] as String? ?? '',
            );
            return timestamp != null &&
                _sameExactTimestamp(timestamp, officialTimestamp);
          })
          .toList(growable: false);
      if (exactPending.length > 1) {
        throw StateError('MULTIPLE_PENDING_DRAFTS_FOR_DELETED_FORMAL_INVOICE');
      }
      if (exactPending.length == 1) {
        final row = exactPending.single;
        final draftId = row['id'] as String?;
        final existingReference = row['candidate_reference'] as String?;
        if (draftId == null || draftId.trim().isEmpty) {
          throw StateError('PENDING_DRAFT_ID_MISSING');
        }
        if (existingReference == null ||
            (candidateReferences.isNotEmpty &&
                !candidateReferences.contains(existingReference))) {
          throw StateError('PENDING_DRAFT_CANDIDATE_REFERENCE_CONFLICT');
        }
        final changed = await transaction.update(
          'cloud_invoice_drafts',
          <String, Object?>{
            'account_id': account?.id ?? '',
            'account_name': account?.displayName ?? '',
            'account_resolution_status': account == null
                ? 'unresolved'
                : 'selected',
            'amount': refreshCandidate.totalAmount,
            'invoice_date': refreshCandidate.invoiceDate.toIso8601String(),
            'time_precision': refreshRequest.facts.timePrecision.name,
            'time_source': refreshRequest.facts.timeSource.name,
            'currency_code': refreshRequest.facts.hasKnownCurrency
                ? refreshRequest.facts.currencyCode!.trim().toUpperCase()
                : null,
            'currency_source': refreshRequest.facts.currencySource.name,
            'merchant_id': null,
            'invoice_number': refreshCandidate.invoiceNumber,
            'seller_identifier': refreshCandidate.sellerIdentifier,
            'seller_name': refreshCandidate.sellerName,
            'tax_amount': refreshCandidate.taxAmount,
            'line_items_json': encodeCloudInvoiceLineItems(
              refreshCandidate.lineItems,
            ),
            'payload_version': canonicalCloudInvoicePayloadVersion,
          },
          where: 'id = ?',
          whereArgs: <Object?>[draftId],
        );
        if (changed != 1) {
          throw StateError('PENDING_DRAFT_REFRESH_FAILED');
        }
        return;
      }

      for (final candidateReference in candidateReferences) {
        final abandonedOperations = await transaction.rawQuery(
          '''
          SELECT o.operation_key
          FROM cloud_invoice_operations o
          LEFT JOIN cloud_invoice_drafts d ON d.id = o.draft_id
          WHERE o.candidate_reference = ?
            AND o.action = 'createNewDraft'
            AND d.id IS NULL
          ''',
          <Object?>[candidateReference],
        );
        for (final operation in abandonedOperations) {
          await transaction.delete(
            'cloud_invoice_operations',
            where: 'operation_key = ?',
            whereArgs: <Object?>[operation['operation_key']],
          );
        }
      }
    });
  }
}

String normalizedOfficialInvoiceNumber(OfficialInvoiceDetailEnrichment item) {
  final value = item.invoiceNumber.trim().isNotEmpty
      ? item.invoiceNumber
      : item.requestedInvoiceNumber;
  return normalizeInvoiceNumber(value);
}

String normalizeInvoiceNumber(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

bool _sameExactTimestamp(DateTime left, DateTime right) {
  if (left.isAtSameMomentAs(right)) return true;
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day &&
      left.hour == right.hour &&
      left.minute == right.minute &&
      left.second == right.second;
}
