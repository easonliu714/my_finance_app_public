import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';

import '../../../database/production_database_coordinator.dart';
import '../../account/account_record.dart';
import '../../transaction/transaction_record.dart';
import '../../transaction/transaction_type.dart';
import '../cloud_invoice_candidate.dart';
import 'canonical_cloud_invoice_persistence_service.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_reconciliation_models.dart';
import 'cloud_invoice_reconciliation_review_decision.dart';
import 'official_cloud_invoice_csv_adapter.dart';
import 'official_invoice_detail_enrichment.dart';
import 'official_invoice_detail_enrichment_repository.dart';
import 'private_cloud_invoice_csv_reconciliation_preview.dart';

class PrivateCloudInvoiceCsvSource {
  const PrivateCloudInvoiceCsvSource({
    required this.fileName,
    required this.preview,
  });

  final String fileName;
  final OfficialCloudInvoiceCsvPreview preview;
}

class PrivateCloudInvoiceCsvImportSummary {
  const PrivateCloudInvoiceCsvImportSummary({
    required this.results,
    required this.transactionCountUnchanged,
    this.invoiceNumberByOperationKey = const <String, String>{},
  });

  final List<CloudInvoicePersistenceResult> results;
  final bool transactionCountUnchanged;
  final Map<String, String> invoiceNumberByOperationKey;

  int get committedCount => results
      .where((item) => item.status == CloudInvoicePersistenceStatus.committed)
      .length;

  int get replayCount => results
      .where(
        (item) => item.status == CloudInvoicePersistenceStatus.alreadyApplied,
      )
      .length;

  int get rejectedCount => results.length - committedCount - replayCount;

  Set<String> get pendingDraftIds => results
      .where(
        (item) =>
            item.draftId != null &&
            (item.status == CloudInvoicePersistenceStatus.committed ||
                item.status == CloudInvoicePersistenceStatus.alreadyApplied),
      )
      .map((item) => item.draftId!)
      .toSet();

  String invoiceNumberFor(CloudInvoicePersistenceResult result) =>
      invoiceNumberByOperationKey[result.operationKey] ?? result.operationKey;
}

abstract interface class PrivateCloudInvoiceCsvImportPort {
  Future<PrivateCloudInvoiceCsvSource?> pickAndPreview();

  Future<PrivateCloudInvoiceCsvReconciliationPreview>
  buildReconciliationPreview(OfficialCloudInvoiceCsvPreview preview);

  Future<List<AccountRecord>> listActiveAccounts();

  Future<PrivateCloudInvoiceCsvImportSummary> importDrafts({
    required OfficialCloudInvoiceCsvPreview preview,
    required Set<String> invoiceIds,
    required AccountRecord account,
  });
}

class PrivateCloudInvoiceCsvImportService
    implements PrivateCloudInvoiceCsvImportPort {
  PrivateCloudInvoiceCsvImportService({
    Future<Database> Function()? databaseProvider,
    CanonicalCloudInvoicePersistenceService? persistenceService,
    OfficialCloudInvoiceCsvAdapter? adapter,
    OfficialInvoiceDetailEnrichmentRepository? detailEnrichmentRepository,
    PrivateCloudInvoiceCsvReconciliationPreviewBuilder? reconciliationBuilder,
    DateTime Function()? clock,
  }) : _databaseProvider =
           databaseProvider ??
           (() => ProductionDatabaseCoordinator.instance.database),
       _persistenceService =
           persistenceService ?? CanonicalCloudInvoicePersistenceService(),
       _adapter = adapter ?? const OfficialCloudInvoiceCsvAdapter(),
       _detailEnrichmentRepository =
           detailEnrichmentRepository ??
           OfficialInvoiceDetailEnrichmentRepository(
             databaseProvider:
                 databaseProvider ??
                 (() => ProductionDatabaseCoordinator.instance.database),
           ),
       _reconciliationBuilder =
           reconciliationBuilder ??
           const PrivateCloudInvoiceCsvReconciliationPreviewBuilder(),
       _clock = clock ?? DateTime.now;

  final Future<Database> Function() _databaseProvider;
  final CanonicalCloudInvoicePersistenceService _persistenceService;
  final OfficialCloudInvoiceCsvAdapter _adapter;
  final OfficialInvoiceDetailEnrichmentRepository _detailEnrichmentRepository;
  final PrivateCloudInvoiceCsvReconciliationPreviewBuilder
  _reconciliationBuilder;
  final DateTime Function() _clock;

  @override
  Future<PrivateCloudInvoiceCsvSource?> pickAndPreview() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['csv'],
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) {
      return null;
    }

    final bytes = await _readBytes(file);
    final decoded = utf8.decode(bytes, allowMalformed: false);
    return PrivateCloudInvoiceCsvSource(
      fileName: file.name,
      preview: _adapter.createPreview(decoded),
    );
  }

  Future<Uint8List> _readBytes(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }

    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const FileSystemException('CSV_FILE_NOT_READABLE');
    }
    return File(path).readAsBytes();
  }

  @override
  Future<PrivateCloudInvoiceCsvReconciliationPreview>
  buildReconciliationPreview(OfficialCloudInvoiceCsvPreview preview) async {
    final supportedCandidates = preview.invoices
        .where((invoice) => invoice.isSupported && invoice.candidate != null)
        .map((invoice) => invoice.candidate!)
        .toList(growable: false);
    final db = await _databaseProvider();
    final existingLinks = await _loadExistingLinks(db, supportedCandidates);

    if (supportedCandidates.isEmpty) {
      return _reconciliationBuilder.build(
        csvPreview: preview,
        localTransactions: const <TransactionRecord>[],
        existingLinksByInvoiceNumber: existingLinks,
      );
    }

    final supportedDates =
        supportedCandidates
            .map((candidate) => candidate.invoiceDate)
            .toList(growable: false)
          ..sort();
    final first = supportedDates.first;
    final last = supportedDates.last;
    final start = DateTime(first.year, first.month, first.day);
    final endExclusive = DateTime(last.year, last.month, last.day + 1);
    final rows = await db.query(
      'transactions',
      where: 'type = ? AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: <Object?>[
        TransactionType.expense.name,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
      orderBy: 'occurred_at ASC, created_at ASC',
    );

    return _reconciliationBuilder.build(
      csvPreview: preview,
      localTransactions: rows
          .map(TransactionRecord.fromMap)
          .toList(growable: false),
      existingLinksByInvoiceNumber: existingLinks,
    );
  }

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
  Future<PrivateCloudInvoiceCsvImportSummary> importDrafts({
    required OfficialCloudInvoiceCsvPreview preview,
    required Set<String> invoiceIds,
    required AccountRecord account,
  }) async {
    final candidates = preview.importSelected(invoiceIds);
    final db = await _databaseProvider();
    final existingLinks = await _loadExistingLinks(db, candidates);
    final protectedInvoiceNumbers = candidates
        .map(
          (candidate) => normalizeCloudInvoiceNumber(candidate.invoiceNumber),
        )
        .where(existingLinks.containsKey)
        .toSet();
    if (protectedInvoiceNumbers.isNotEmpty) {
      throw StateError('CSV_CANONICAL_LINK_REVIEW_REQUIRED');
    }

    final enrichments = await _detailEnrichmentRepository.loadByInvoiceNumbers(
      candidates.map((candidate) => candidate.invoiceNumber),
    );
    final before = await _countTransactions(db);
    final results = <CloudInvoicePersistenceResult>[];
    final invoiceNumberByOperationKey = <String, String>{};

    for (final candidate in candidates) {
      final normalizedInvoiceNumber = normalizeCloudInvoiceNumber(
        candidate.invoiceNumber,
      );
      final pendingDraft = await _loadPendingDraft(
        db,
        normalizedInvoiceNumber,
        account,
      );
      if (pendingDraft != null) {
        results.add(pendingDraft);
        invoiceNumberByOperationKey[pendingDraft.operationKey] =
            normalizedInvoiceNumber;
        continue;
      }

      final enrichment = enrichments[normalizedInvoiceNumber];
      final request = buildRequest(account, candidate, enrichment: enrichment);
      final result = await _persistenceService.execute(request);
      results.add(result);
      invoiceNumberByOperationKey[result.operationKey] =
          normalizedInvoiceNumber;
    }

    final after = await _countTransactions(db);
    return PrivateCloudInvoiceCsvImportSummary(
      results: List<CloudInvoicePersistenceResult>.unmodifiable(results),
      transactionCountUnchanged: before == after,
      invoiceNumberByOperationKey: Map<String, String>.unmodifiable(
        invoiceNumberByOperationKey,
      ),
    );
  }

  CloudInvoicePersistenceRequest buildRequest(
    AccountRecord account,
    CloudInvoiceCandidate candidate, {
    OfficialInvoiceDetailEnrichment? enrichment,
  }) {
    final acceptedEnrichment =
        enrichment != null && enrichment.isCompatibleWithCandidate(candidate)
        ? enrichment
        : null;
    final enrichedCandidate =
        acceptedEnrichment?.applyValidatedValues(candidate) ?? candidate;
    final hasExactTime = acceptedEnrichment?.canUpgradeTime == true;
    final hasCurrency = acceptedEnrichment?.canUpgradeCurrency == true;
    final now = _clock().toUtc();
    return CloudInvoicePersistenceRequest(
      facts: CloudInvoiceCandidateFacts(
        candidate: enrichedCandidate,
        timePrecision: hasExactTime
            ? CloudInvoiceTimePrecision.exactDateTime
            : CloudInvoiceTimePrecision.dateOnly,
        timeSource: hasExactTime
            ? CloudInvoiceTimeSource.officialDetailPage
            : CloudInvoiceTimeSource.unknown,
        currencyCode: hasCurrency ? acceptedEnrichment!.currencyCode : null,
        currencySource: hasCurrency
            ? CloudInvoiceCurrencySource.officialDetailPage
            : CloudInvoiceCurrencySource.unknown,
      ),
      decision: CloudInvoiceReconciliationReviewDecision(
        action: CloudInvoiceReconciliationOutcome.createNewDraft,
        selectedTransactionId: null,
        selectedAccountId: account.id,
        merchantProposalReviewed: true,
        merchantProposalConfirmed: false,
        replacementSecondConfirmationCompleted: false,
        candidateReference: candidate.duplicateKey,
        decidedAt: now,
      ),
      expectedAccountFingerprint: accountFingerprint(account),
      requestedAt: now,
    );
  }

  Future<CloudInvoicePersistenceResult?> _loadPendingDraft(
    DatabaseExecutor db,
    String normalizedInvoiceNumber,
    AccountRecord explicitAccount,
  ) async {
    if (normalizedInvoiceNumber.isEmpty) return null;

    final rows = await db.rawQuery(
      '''
      SELECT d.id,
             d.operation_key,
             d.account_id,
             d.account_name,
             d.account_resolution_status
      FROM cloud_invoice_drafts d
      LEFT JOIN cloud_invoice_draft_promotions p ON p.draft_id = d.id
      WHERE UPPER(REPLACE(REPLACE(TRIM(d.invoice_number), ' ', ''), '-', '')) = ?
        AND p.draft_id IS NULL
      ORDER BY d.created_at DESC
      LIMIT 1
      ''',
      <Object?>[normalizedInvoiceNumber],
    );
    if (rows.isEmpty) return null;

    final row = rows.single;
    final draftId = (row['id'] as String? ?? '').trim();
    final operationKey = (row['operation_key'] as String? ?? '').trim();
    var accountId = (row['account_id'] as String? ?? '').trim();
    final resolutionStatus =
        (row['account_resolution_status'] as String? ?? 'selected').trim();
    if (draftId.isEmpty || operationKey.isEmpty) return null;

    // The CSV account selection is an explicit user decision. Carry it into a
    // reused draft only while that draft is still unresolved; never overwrite
    // an account that was already reviewed and selected in an earlier flow.
    if (accountId.isEmpty || resolutionStatus == 'unresolved') {
      await db.update(
        'cloud_invoice_drafts',
        <String, Object?>{
          'account_id': explicitAccount.id,
          'account_name': explicitAccount.displayName,
          'account_resolution_status': 'selected',
        },
        where: 'id = ?',
        whereArgs: <Object?>[draftId],
      );
      accountId = explicitAccount.id;
    }

    return CloudInvoicePersistenceResult(
      status: CloudInvoicePersistenceStatus.alreadyApplied,
      operationKey: operationKey,
      message: 'CSV_INVOICE_DRAFT_ALREADY_PENDING',
      accountId: accountId.isEmpty ? null : accountId,
      draftId: draftId,
    );
  }

  Future<Map<String, PrivateCloudInvoiceCsvExistingLinkLookup>>
  _loadExistingLinks(
    DatabaseExecutor db,
    Iterable<CloudInvoiceCandidate> candidates,
  ) async {
    final normalizedNumbers = candidates
        .map(
          (candidate) => normalizeCloudInvoiceNumber(candidate.invoiceNumber),
        )
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedNumbers.isEmpty) {
      return const <String, PrivateCloudInvoiceCsvExistingLinkLookup>{};
    }

    final placeholders = List<String>.filled(
      normalizedNumbers.length,
      '?',
    ).join(',');
    final linkRows = await db.rawQuery(
      'SELECT invoice_number, transaction_id '
      'FROM cloud_invoice_metadata_links '
      "WHERE UPPER(REPLACE(REPLACE(TRIM(invoice_number), ' ', ''), '-', '')) "
      'IN ($placeholders)',
      normalizedNumbers.toList(growable: false),
    );

    final rowsByInvoice = <String, List<Map<String, Object?>>>{};
    final transactionIds = <String>{};
    for (final row in linkRows) {
      final invoiceNumber = normalizeCloudInvoiceNumber(
        row['invoice_number'] as String? ?? '',
      );
      final transactionId = (row['transaction_id'] as String? ?? '').trim();
      if (!normalizedNumbers.contains(invoiceNumber)) {
        continue;
      }
      rowsByInvoice
          .putIfAbsent(invoiceNumber, () => <Map<String, Object?>>[])
          .add(row);
      if (transactionId.isNotEmpty) {
        transactionIds.add(transactionId);
      }
    }
    if (rowsByInvoice.isEmpty) {
      return const <String, PrivateCloudInvoiceCsvExistingLinkLookup>{};
    }

    final transactionsById = <String, TransactionRecord>{};
    if (transactionIds.isNotEmpty) {
      final transactionPlaceholders = List<String>.filled(
        transactionIds.length,
        '?',
      ).join(',');
      final transactionRows = await db.query(
        'transactions',
        where: 'id IN ($transactionPlaceholders)',
        whereArgs: transactionIds.toList(growable: false),
      );
      for (final row in transactionRows) {
        final transaction = TransactionRecord.fromMap(row);
        transactionsById[transaction.id] = transaction;
      }
    }

    final result = <String, PrivateCloudInvoiceCsvExistingLinkLookup>{};
    for (final entry in rowsByInvoice.entries) {
      final matchesById = <String, PrivateCloudInvoiceCsvTransactionMatch>{};
      for (final row in entry.value) {
        final transactionId = (row['transaction_id'] as String? ?? '').trim();
        final transaction = transactionsById[transactionId];
        if (transaction == null) {
          continue;
        }
        matchesById[transactionId] = PrivateCloudInvoiceCsvTransactionMatch(
          transactionId: transaction.id,
          transactionFingerprint: transactionFingerprint(transaction),
          accountName: transaction.accountName,
          merchantName: transaction.merchantName,
          occurredAt: transaction.occurredAt,
          amount: transaction.amount,
        );
      }
      result[entry.key] = PrivateCloudInvoiceCsvExistingLinkLookup(
        normalizedInvoiceNumber: entry.key,
        linkCount: entry.value.length,
        matches: List<PrivateCloudInvoiceCsvTransactionMatch>.unmodifiable(
          matchesById.values,
        ),
      );
    }
    return Map<String, PrivateCloudInvoiceCsvExistingLinkLookup>.unmodifiable(
      result,
    );
  }

  Future<int> _countTransactions(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM transactions',
    );
    return (rows.single['total'] as num).toInt();
  }
}
