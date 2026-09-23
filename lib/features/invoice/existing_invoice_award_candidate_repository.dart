import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../transaction/transaction_record.dart';

/// How a formal transaction obtained its governed invoice identity.
enum ExistingInvoiceAwardIdentitySource {
  cloudMetadata,
  governedReviewNote,
}

/// Cloud-exclusive eligibility is deliberately tri-state. Existing cloud
/// metadata proves invoice identity, not every statutory eligibility fact.
enum ExistingInvoiceAwardCloudEligibility {
  eligible,
  ineligible,
  unknownReviewRequired,
}

class ExistingInvoiceAwardCandidate {
  const ExistingInvoiceAwardCandidate({
    required this.transactionId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.awardPeriod,
    required this.identitySource,
    required this.sourceProvenance,
    required this.cloudEligibility,
  });

  final String transactionId;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String awardPeriod;
  final ExistingInvoiceAwardIdentitySource identitySource;
  final String sourceProvenance;
  final ExistingInvoiceAwardCloudEligibility cloudEligibility;

  String get dedupeKey => '$transactionId|$invoiceNumber|${_dateKey(invoiceDate)}';
}

typedef ExistingInvoiceAwardDatabaseProvider = Future<Database> Function();

/// Read-only projection of governed invoice identities already attached to
/// formal transactions. It never infers invoice identity from merchant/date/
/// amount and never scans arbitrary note text with a loose regex.
class ExistingInvoiceAwardCandidateRepository {
  ExistingInvoiceAwardCandidateRepository({
    ExistingInvoiceAwardDatabaseProvider? databaseProvider,
  }) : _databaseProvider = databaseProvider ??
            (() => ProductionDatabaseCoordinator.instance.database);

  final ExistingInvoiceAwardDatabaseProvider _databaseProvider;

  Future<List<ExistingInvoiceAwardCandidate>> listCandidates() async {
    final db = await _databaseProvider();
    final rows = await db.query('transactions');
    final cloudRows = await _tableExists(db, 'cloud_invoice_metadata_links')
        ? await db.query('cloud_invoice_metadata_links')
        : const <Map<String, Object?>>[];

    final cloudByTransaction = <String, List<Map<String, Object?>>>{};
    for (final row in cloudRows) {
      final transactionId = row['transaction_id']?.toString().trim() ?? '';
      if (transactionId.isEmpty) continue;
      cloudByTransaction.putIfAbsent(transactionId, () => []).add(row);
    }

    final candidates = <ExistingInvoiceAwardCandidate>[];
    final seen = <String>{};
    for (final row in rows) {
      final transaction = TransactionRecord.fromMap(row);
      final cloud = _cloudCandidate(transaction, cloudByTransaction[transaction.id]);
      final candidate = cloud ?? _governedNoteCandidate(transaction);
      if (candidate != null && seen.add(candidate.dedupeKey)) {
        candidates.add(candidate);
      }
    }
    candidates.sort((a, b) {
      final date = b.invoiceDate.compareTo(a.invoiceDate);
      return date != 0 ? date : a.transactionId.compareTo(b.transactionId);
    });
    return List<ExistingInvoiceAwardCandidate>.unmodifiable(candidates);
  }

  ExistingInvoiceAwardCandidate? _cloudCandidate(
    TransactionRecord transaction,
    List<Map<String, Object?>>? links,
  ) {
    if (links == null || links.isEmpty) return null;
    final identities = <String, ExistingInvoiceAwardCandidate>{};
    for (final link in links) {
      final number = _normalizeInvoiceNumber(link['invoice_number']?.toString() ?? '');
      final date = DateTime.tryParse(link['invoice_date']?.toString() ?? '');
      if (number == null || date == null) continue;
      final period = _periodForDate(date);
      final candidate = ExistingInvoiceAwardCandidate(
        transactionId: transaction.id,
        invoiceNumber: number,
        invoiceDate: date,
        awardPeriod: period,
        identitySource: ExistingInvoiceAwardIdentitySource.cloudMetadata,
        sourceProvenance: 'cloud_invoice_metadata_links:${link['id'] ?? link['operation_key'] ?? ''}',
        cloudEligibility:
            ExistingInvoiceAwardCloudEligibility.unknownReviewRequired,
      );
      identities['$number|${_dateKey(date)}'] = candidate;
    }
    // Multiple distinct structured identities for one formal transaction are
    // ambiguous and therefore fail closed.
    return identities.length == 1 ? identities.values.single : null;
  }

  ExistingInvoiceAwardCandidate? _governedNoteCandidate(
    TransactionRecord transaction,
  ) {
    final parsed = GovernedInvoiceReviewNoteParser.parse(transaction.note);
    if (parsed == null) return null;
    final period = _periodForDate(transaction.occurredAt);
    if (parsed.invoicePeriod != null && parsed.invoicePeriod != period) {
      return null;
    }
    return ExistingInvoiceAwardCandidate(
      transactionId: transaction.id,
      invoiceNumber: parsed.invoiceNumber,
      invoiceDate: transaction.occurredAt,
      awardPeriod: period,
      identitySource: ExistingInvoiceAwardIdentitySource.governedReviewNote,
      sourceProvenance: GovernedInvoiceReviewNoteParser.sourceMarker,
      cloudEligibility: ExistingInvoiceAwardCloudEligibility.ineligible,
    );
  }

  Future<bool> _tableExists(DatabaseExecutor db, String name) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}

class GovernedInvoiceReviewNote {
  const GovernedInvoiceReviewNote({
    required this.invoiceNumber,
    this.invoicePeriod,
  });

  final String invoiceNumber;
  final String? invoicePeriod;
}

/// Exact parser for notes emitted by InvoiceTransactionHandoffContract only.
/// Unknown/duplicate labels and arbitrary user notes fail closed.
class GovernedInvoiceReviewNoteParser {
  const GovernedInvoiceReviewNoteParser._();

  static const String sourceMarker = '來源：發票辨識人工覆核';
  static const Set<String> _allowedLabels = <String>{
    '發票號碼',
    '賣方統編',
    '發票期別',
    '隨機碼',
  };

  static GovernedInvoiceReviewNote? parse(String note) {
    final lines = note.split('\n');
    if (lines.isEmpty || lines.first != sourceMarker) return null;
    String? invoiceNumber;
    String? invoicePeriod;
    final seen = <String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line == '品項明細：') break;
      if (line.isEmpty || line.startsWith('- ')) return null;
      final separator = line.indexOf('：');
      if (separator <= 0) return null;
      final label = line.substring(0, separator);
      final value = line.substring(separator + 1);
      if (!_allowedLabels.contains(label) || value.isEmpty || !seen.add(label)) {
        return null;
      }
      if (label == '發票號碼') invoiceNumber = _normalizeInvoiceNumber(value);
      if (label == '發票期別') invoicePeriod = _normalizePeriod(value);
    }
    if (invoiceNumber == null) return null;
    return GovernedInvoiceReviewNote(
      invoiceNumber: invoiceNumber,
      invoicePeriod: invoicePeriod,
    );
  }
}

String? _normalizeInvoiceNumber(String raw) {
  final value = raw.trim().toUpperCase().replaceAll('-', '');
  return RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(value) ? value : null;
}

String? _normalizePeriod(String raw) {
  final value = raw.trim().replaceAll(RegExp(r'\s+'), '');
  final compact = RegExp(r'^(\d{3})(\d{2})$').firstMatch(value);
  if (compact != null) return '${compact.group(1)}/${compact.group(2)}';
  final separated = RegExp(r'^(\d{3})[/\-](\d{1,2})$').firstMatch(value);
  if (separated == null) return null;
  final month = int.tryParse(separated.group(2)!);
  if (month == null || month < 1 || month > 12) return null;
  return '${separated.group(1)}/${month.toString().padLeft(2, '0')}';
}

String _periodForDate(DateTime date) {
  final rocYear = date.year - 1911;
  final endMonth = date.month.isEven ? date.month : date.month + 1;
  return '$rocYear/${endMonth.toString().padLeft(2, '0')}';
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
