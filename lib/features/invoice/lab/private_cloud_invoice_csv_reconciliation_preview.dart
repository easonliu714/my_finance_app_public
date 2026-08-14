import '../../transaction/transaction_record.dart';
import '../../transaction/transaction_type.dart';
import 'cloud_invoice_persistence_models.dart';
import 'official_cloud_invoice_csv_adapter.dart';

const String privateCloudInvoiceCsvAlreadyLinkedLabel =
    '已存在且已連結交易（預設略過）';

String normalizeCloudInvoiceNumber(String value) {
  return value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
}

enum PrivateCloudInvoiceCsvReconciliationStatus {
  uniqueExistingMatch,
  ambiguousExistingMatch,
  unmatched,
  blocked,
}

enum PrivateCloudInvoiceCsvCanonicalLinkStatus {
  none,
  alreadyLinked,
  brokenOrAmbiguous,
}

enum PrivateCloudInvoiceCsvBlockReason {
  sourceValidation,
  brokenOrAmbiguousCanonicalLink,
}

class PrivateCloudInvoiceCsvTransactionMatch {
  const PrivateCloudInvoiceCsvTransactionMatch({
    required this.transactionId,
    required this.transactionFingerprint,
    required this.accountName,
    required this.merchantName,
    required this.occurredAt,
    required this.amount,
  });

  final String transactionId;
  final String transactionFingerprint;
  final String accountName;
  final String merchantName;
  final DateTime occurredAt;
  final double amount;
}

class PrivateCloudInvoiceCsvExistingLinkLookup {
  const PrivateCloudInvoiceCsvExistingLinkLookup({
    required this.normalizedInvoiceNumber,
    required this.linkCount,
    required this.matches,
  });

  final String normalizedInvoiceNumber;
  final int linkCount;
  final List<PrivateCloudInvoiceCsvTransactionMatch> matches;

  bool get isExactlyOneValidLink => linkCount == 1 && matches.length == 1;
  bool get isBrokenOrAmbiguous => linkCount > 0 && !isExactlyOneValidLink;
}

class PrivateCloudInvoiceCsvReconciliationItem {
  const PrivateCloudInvoiceCsvReconciliationItem({
    required this.invoice,
    required this.status,
    required this.matches,
    this.canonicalLinkStatus = PrivateCloudInvoiceCsvCanonicalLinkStatus.none,
    this.blockReason,
  });

  final OfficialCloudInvoiceCsvInvoicePreview invoice;
  final PrivateCloudInvoiceCsvReconciliationStatus status;
  final List<PrivateCloudInvoiceCsvTransactionMatch> matches;
  final PrivateCloudInvoiceCsvCanonicalLinkStatus canonicalLinkStatus;
  final PrivateCloudInvoiceCsvBlockReason? blockReason;

  bool get isAlreadyLinked =>
      canonicalLinkStatus ==
      PrivateCloudInvoiceCsvCanonicalLinkStatus.alreadyLinked;
  bool get isDefaultSkipped => isAlreadyLinked;
  PrivateCloudInvoiceCsvTransactionMatch? get linkedTransaction =>
      isAlreadyLinked && matches.length == 1 ? matches.single : null;
  bool get canEnrichExisting =>
      status == PrivateCloudInvoiceCsvReconciliationStatus.uniqueExistingMatch;
  bool get requiresUserMatchChoice =>
      status == PrivateCloudInvoiceCsvReconciliationStatus.ambiguousExistingMatch;
  bool get requiresAccountLater =>
      status == PrivateCloudInvoiceCsvReconciliationStatus.unmatched;
  bool get isBlocked =>
      status == PrivateCloudInvoiceCsvReconciliationStatus.blocked;
}

class PrivateCloudInvoiceCsvReconciliationPreview {
  const PrivateCloudInvoiceCsvReconciliationPreview({
    required this.csvPreview,
    required this.items,
  });

  final OfficialCloudInvoiceCsvPreview csvPreview;
  final List<PrivateCloudInvoiceCsvReconciliationItem> items;

  int get alreadyLinkedCount =>
      items.where((item) => item.isAlreadyLinked).length;
  int get uniqueMatchCount => items
      .where(
        (item) =>
            !item.isAlreadyLinked &&
            item.status ==
                PrivateCloudInvoiceCsvReconciliationStatus.uniqueExistingMatch,
      )
      .length;
  int get ambiguousMatchCount =>
      _count(PrivateCloudInvoiceCsvReconciliationStatus.ambiguousExistingMatch);
  int get unmatchedCount =>
      _count(PrivateCloudInvoiceCsvReconciliationStatus.unmatched);
  int get blockedCount =>
      _count(PrivateCloudInvoiceCsvReconciliationStatus.blocked);
  bool get requiresAccountSelectionNow => false;

  int _count(PrivateCloudInvoiceCsvReconciliationStatus status) {
    return items.where((item) => item.status == status).length;
  }
}

class PrivateCloudInvoiceCsvReconciliationPreviewBuilder {
  const PrivateCloudInvoiceCsvReconciliationPreviewBuilder({
    this.amountTolerance = 0.01,
  });

  final double amountTolerance;

  PrivateCloudInvoiceCsvReconciliationPreview build({
    required OfficialCloudInvoiceCsvPreview csvPreview,
    required List<TransactionRecord> localTransactions,
    Map<String, PrivateCloudInvoiceCsvExistingLinkLookup>
        existingLinksByInvoiceNumber =
        const <String, PrivateCloudInvoiceCsvExistingLinkLookup>{},
  }) {
    final expenseTransactions = localTransactions
        .where((transaction) => transaction.type == TransactionType.expense)
        .toList(growable: false);

    return PrivateCloudInvoiceCsvReconciliationPreview(
      csvPreview: csvPreview,
      items: List<PrivateCloudInvoiceCsvReconciliationItem>.unmodifiable(
        csvPreview.invoices.map(
          (invoice) => _buildItem(
            invoice: invoice,
            localTransactions: expenseTransactions,
            existingLinksByInvoiceNumber: existingLinksByInvoiceNumber,
          ),
        ),
      ),
    );
  }

  PrivateCloudInvoiceCsvReconciliationItem _buildItem({
    required OfficialCloudInvoiceCsvInvoicePreview invoice,
    required List<TransactionRecord> localTransactions,
    required Map<String, PrivateCloudInvoiceCsvExistingLinkLookup>
        existingLinksByInvoiceNumber,
  }) {
    final candidate = invoice.candidate;
    if (!invoice.isSupported || candidate == null) {
      return PrivateCloudInvoiceCsvReconciliationItem(
        invoice: invoice,
        status: PrivateCloudInvoiceCsvReconciliationStatus.blocked,
        matches: const <PrivateCloudInvoiceCsvTransactionMatch>[],
        blockReason: PrivateCloudInvoiceCsvBlockReason.sourceValidation,
      );
    }

    final normalizedInvoiceNumber =
        normalizeCloudInvoiceNumber(candidate.invoiceNumber);
    final existingLink =
        existingLinksByInvoiceNumber[normalizedInvoiceNumber];
    if (existingLink != null && existingLink.isExactlyOneValidLink) {
      return PrivateCloudInvoiceCsvReconciliationItem(
        invoice: invoice,
        status: PrivateCloudInvoiceCsvReconciliationStatus.uniqueExistingMatch,
        canonicalLinkStatus:
            PrivateCloudInvoiceCsvCanonicalLinkStatus.alreadyLinked,
        matches: List<PrivateCloudInvoiceCsvTransactionMatch>.unmodifiable(
          existingLink.matches,
        ),
      );
    }
    if (existingLink != null && existingLink.isBrokenOrAmbiguous) {
      return PrivateCloudInvoiceCsvReconciliationItem(
        invoice: invoice,
        status: PrivateCloudInvoiceCsvReconciliationStatus.blocked,
        canonicalLinkStatus:
            PrivateCloudInvoiceCsvCanonicalLinkStatus.brokenOrAmbiguous,
        matches: List<PrivateCloudInvoiceCsvTransactionMatch>.unmodifiable(
          existingLink.matches,
        ),
        blockReason:
            PrivateCloudInvoiceCsvBlockReason.brokenOrAmbiguousCanonicalLink,
      );
    }

    final matches = localTransactions
        .where(
          (transaction) =>
              _sameDate(transaction.occurredAt, candidate.invoiceDate) &&
              (transaction.amount - candidate.totalAmount).abs() <=
                  amountTolerance,
        )
        .map(_toMatch)
        .toList(growable: false);

    final status = matches.length == 1
        ? PrivateCloudInvoiceCsvReconciliationStatus.uniqueExistingMatch
        : matches.length > 1
            ? PrivateCloudInvoiceCsvReconciliationStatus.ambiguousExistingMatch
            : PrivateCloudInvoiceCsvReconciliationStatus.unmatched;

    return PrivateCloudInvoiceCsvReconciliationItem(
      invoice: invoice,
      status: status,
      matches: List<PrivateCloudInvoiceCsvTransactionMatch>.unmodifiable(
        matches,
      ),
    );
  }

  PrivateCloudInvoiceCsvTransactionMatch _toMatch(
    TransactionRecord transaction,
  ) {
    return PrivateCloudInvoiceCsvTransactionMatch(
      transactionId: transaction.id,
      transactionFingerprint: transactionFingerprint(transaction),
      accountName: transaction.accountName,
      merchantName: transaction.merchantName,
      occurredAt: transaction.occurredAt,
      amount: transaction.amount,
    );
  }

  bool _sameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
