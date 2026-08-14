import '../../account/account_record.dart';
import '../../merchant/merchant_record.dart';
import '../../transaction/transaction_record.dart';
import '../cloud_invoice_candidate.dart';

enum CloudInvoiceTimePrecision {
  dateOnly,
  exactDateTime,
}

enum CloudInvoiceTimeSource {
  unknown,
  officialInvoiceIssuedAt,
  officialDetailPage,
  merchantPosCheckout,
  emailReceipt,
  invoiceQrCode,
  userEntered,
}

enum CloudInvoiceCurrencySource {
  unknown,
  officialDetail,
  officialDetailPage,
  merchantData,
  loyaltyAppDisplay,
  inferredDefault,
  userConfirmed,
}

class CloudInvoicePaymentHint {
  const CloudInvoicePaymentHint({
    this.accountName,
    this.accountType,
    this.methodLabel,
  });

  final String? accountName;
  final AccountType? accountType;
  final String? methodLabel;

  bool get hasAnyValue =>
      _hasText(accountName) || accountType != null || _hasText(methodLabel);

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class CloudInvoiceCandidateFacts {
  const CloudInvoiceCandidateFacts({
    required this.candidate,
    this.timePrecision = CloudInvoiceTimePrecision.dateOnly,
    this.timeSource = CloudInvoiceTimeSource.unknown,
    this.currencyCode,
    this.currencySource = CloudInvoiceCurrencySource.unknown,
    this.paymentHint = const CloudInvoicePaymentHint(),
  });

  final CloudInvoiceCandidate candidate;
  final CloudInvoiceTimePrecision timePrecision;
  final CloudInvoiceTimeSource timeSource;
  final String? currencyCode;
  final CloudInvoiceCurrencySource currencySource;
  final CloudInvoicePaymentHint paymentHint;

  bool get hasExactTime =>
      timePrecision == CloudInvoiceTimePrecision.exactDateTime;

  bool get hasKnownCurrency =>
      currencyCode != null && currencyCode!.trim().isNotEmpty;

  DateTime get invoiceDateOnly => DateTime(
        candidate.invoiceDate.year,
        candidate.invoiceDate.month,
        candidate.invoiceDate.day,
      );
}

class LocalTransactionReconciliationSnapshot {
  const LocalTransactionReconciliationSnapshot({
    required this.transaction,
    this.invoiceNumber,
    this.sellerIdentifier,
    this.sourceReferenceId,
  });

  final TransactionRecord transaction;
  final String? invoiceNumber;
  final String? sellerIdentifier;
  final String? sourceReferenceId;
}

enum CloudInvoiceMatchSignal {
  sameCalendarDate,
  exactAmount,
  invoiceIdentity,
  merchantExact,
  merchantSimilar,
  accountNameMatch,
  accountTypeMatch,
  paymentMethodMatch,
  amountConflict,
  merchantConflict,
  currencyConflict,
}

enum CloudInvoiceReconciliationOutcome {
  exactDuplicate,
  enrichExisting,
  replaceExisting,
  createNewDraft,
  keepSeparate,
  ambiguous,
  blocked,
}

class CloudInvoiceTransactionMatch {
  const CloudInvoiceTransactionMatch({
    required this.snapshot,
    required this.score,
    required this.signals,
    required this.recommendedOutcome,
    required this.canOfferReplacement,
  });

  final LocalTransactionReconciliationSnapshot snapshot;
  final int score;
  final Set<CloudInvoiceMatchSignal> signals;
  final CloudInvoiceReconciliationOutcome recommendedOutcome;
  final bool canOfferReplacement;

  bool get hasExactAmount =>
      signals.contains(CloudInvoiceMatchSignal.exactAmount);
  bool get hasMerchantEvidence =>
      signals.contains(CloudInvoiceMatchSignal.merchantExact) ||
      signals.contains(CloudInvoiceMatchSignal.merchantSimilar);
  bool get hasPaymentEvidence =>
      signals.contains(CloudInvoiceMatchSignal.accountNameMatch) ||
      signals.contains(CloudInvoiceMatchSignal.accountTypeMatch) ||
      signals.contains(CloudInvoiceMatchSignal.paymentMethodMatch);
  bool get hasCurrencyConflict =>
      signals.contains(CloudInvoiceMatchSignal.currencyConflict);
}

enum CloudInvoiceMerchantResolutionStatus {
  linkedExisting,
  createDraftProposed,
  unresolved,
}

class CloudInvoiceMerchantCreationProposal {
  const CloudInvoiceMerchantCreationProposal({
    required this.name,
    required this.sellerIdentifier,
    required this.sourceInvoiceNumber,
  });

  final String name;
  final String sellerIdentifier;
  final String sourceInvoiceNumber;

  bool get requiresUserConfirmation => true;
  bool get canPersistAutomatically => false;
}

class CloudInvoiceMerchantResolutionPlan {
  const CloudInvoiceMerchantResolutionPlan({
    required this.status,
    this.existingMerchant,
    this.creationProposal,
  });

  final CloudInvoiceMerchantResolutionStatus status;
  final MerchantRecord? existingMerchant;
  final CloudInvoiceMerchantCreationProposal? creationProposal;

  bool get requiresUserConfirmation =>
      status != CloudInvoiceMerchantResolutionStatus.linkedExisting;
}

class CloudInvoiceAccountSelectionOption {
  const CloudInvoiceAccountSelectionOption({
    required this.account,
    required this.currencyCompatible,
    required this.matchesHint,
  });

  final AccountRecord account;
  final bool currencyCompatible;
  final bool matchesHint;
}

enum CloudInvoiceAccountResolutionStatus {
  preservedExisting,
  selectionRequired,
  newAccountRequired,
}

class CloudInvoiceAccountResolutionPlan {
  const CloudInvoiceAccountResolutionPlan({
    required this.status,
    required this.options,
    this.preservedAccountName,
    this.suggestedAccountId,
  });

  final CloudInvoiceAccountResolutionStatus status;
  final List<CloudInvoiceAccountSelectionOption> options;
  final String? preservedAccountName;
  final String? suggestedAccountId;

  bool get requiresUserSelection =>
      status == CloudInvoiceAccountResolutionStatus.selectionRequired;
  bool get requiresNewAccount =>
      status == CloudInvoiceAccountResolutionStatus.newAccountRequired;
  bool get canAddNewAccount => true;
  bool get canCreateFormalTransaction => false;
}

enum CloudInvoiceReconciliationField {
  invoiceNumber,
  sellerIdentifier,
  merchantName,
  amount,
  transactionDate,
  exactTime,
  currency,
  taxAmount,
  lineItems,
  account,
}

class CloudInvoiceFieldDifference {
  const CloudInvoiceFieldDifference({
    required this.field,
    required this.existingValue,
    required this.candidateValue,
    required this.isMaterialConflict,
    required this.isSafeEnrichment,
  });

  final CloudInvoiceReconciliationField field;
  final String? existingValue;
  final String? candidateValue;
  final bool isMaterialConflict;
  final bool isSafeEnrichment;
}

class CloudInvoiceReconciliationPlan {
  const CloudInvoiceReconciliationPlan({
    required this.recommendedOutcome,
    required this.rankedMatches,
    required this.allowedActions,
    required this.merchantPlan,
    required this.accountPlan,
    required this.fieldDifferences,
    required this.reasons,
  });

  final CloudInvoiceReconciliationOutcome recommendedOutcome;
  final List<CloudInvoiceTransactionMatch> rankedMatches;
  final Set<CloudInvoiceReconciliationOutcome> allowedActions;
  final CloudInvoiceMerchantResolutionPlan merchantPlan;
  final CloudInvoiceAccountResolutionPlan accountPlan;
  final List<CloudInvoiceFieldDifference> fieldDifferences;
  final List<String> reasons;

  bool get requiresUserReview => true;
  bool get canWriteFormalTransactionAutomatically => false;
  bool get canReplaceAutomatically => false;
  bool get hasExistingMatch => rankedMatches.isNotEmpty;
}
