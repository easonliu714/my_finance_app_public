import '../../account/account_record.dart';
import '../../merchant/merchant_record.dart';
import '../cloud_invoice_candidate.dart';
import 'cloud_invoice_reconciliation_models.dart';

class CloudInvoiceReconciliationEngine {
  const CloudInvoiceReconciliationEngine({this.amountTolerance = 0.01});

  final double amountTolerance;

  CloudInvoiceReconciliationPlan reconcile({
    required CloudInvoiceCandidateFacts facts,
    required List<LocalTransactionReconciliationSnapshot> transactions,
    required List<AccountRecord> accounts,
    required List<MerchantRecord> merchants,
  }) {
    final candidate = facts.candidate;
    final merchantPlan = _resolveMerchant(candidate, merchants);

    if (_isBlocked(candidate)) {
      return CloudInvoiceReconciliationPlan(
        recommendedOutcome: CloudInvoiceReconciliationOutcome.blocked,
        rankedMatches: const <CloudInvoiceTransactionMatch>[],
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.blocked,
        },
        merchantPlan: merchantPlan,
        accountPlan: _newDraftAccountPlan(facts, accounts),
        fieldDifferences: const <CloudInvoiceFieldDifference>[],
        reasons: const <String>['候選資料目前不可進入帳目比對。'],
      );
    }

    final matches = transactions
        .where(
          (snapshot) => _sameDate(
            candidate.invoiceDate,
            snapshot.transaction.occurredAt,
          ),
        )
        .map(
          (snapshot) => _evaluate(
            facts: facts,
            snapshot: snapshot,
            accounts: accounts,
          ),
        )
        .toList()
      ..sort(_compareMatches);

    final exact = matches
        .where(
          (match) =>
              match.recommendedOutcome ==
              CloudInvoiceReconciliationOutcome.exactDuplicate,
        )
        .toList();
    final enrich = matches
        .where(
          (match) =>
              match.recommendedOutcome ==
              CloudInvoiceReconciliationOutcome.enrichExisting,
        )
        .toList();
    final amountOnly = matches
        .where(
          (match) =>
              match.recommendedOutcome ==
              CloudInvoiceReconciliationOutcome.ambiguous,
        )
        .toList();
    final relatedSeparate = matches
        .where(
          (match) =>
              match.hasMerchantEvidence ||
              match.hasPaymentEvidence ||
              match.canOfferReplacement,
        )
        .toList();

    late final CloudInvoiceReconciliationOutcome outcome;
    LocalTransactionReconciliationSnapshot? selected;
    final reasons = <String>[];

    if (exact.length == 1) {
      outcome = CloudInvoiceReconciliationOutcome.exactDuplicate;
      selected = exact.single.snapshot;
      reasons.add('找到唯一的發票身分、日期與金額一致帳目。');
    } else if (exact.length > 1) {
      outcome = CloudInvoiceReconciliationOutcome.ambiguous;
      reasons.add('多筆帳目具有相同發票身分，必須人工選擇。');
    } else if (enrich.length == 1) {
      outcome = CloudInvoiceReconciliationOutcome.enrichExisting;
      selected = enrich.single.snapshot;
      reasons.add('找到唯一的同日、同額且具商家或付款證據帳目。');
    } else if (enrich.length > 1) {
      outcome = CloudInvoiceReconciliationOutcome.ambiguous;
      reasons.add('多筆帳目同日同額且均有輔助證據，必須人工選擇。');
    } else if (amountOnly.isNotEmpty) {
      outcome = CloudInvoiceReconciliationOutcome.ambiguous;
      reasons.add('只有日期與金額一致，證據不足以認定同一筆交易。');
    } else if (relatedSeparate.isNotEmpty) {
      outcome = CloudInvoiceReconciliationOutcome.keepSeparate;
      reasons.add('存在同日相關帳目但金額或其他重要欄位衝突，預設保持分開。');
    } else {
      outcome = CloudInvoiceReconciliationOutcome.createNewDraft;
      reasons.add('沒有足夠證據可連結既有帳目，建立待確認草稿。');
    }

    if (facts.timePrecision == CloudInvoiceTimePrecision.dateOnly) {
      reasons.add('雲端資料只有日期；同日 00:00 至 23:59 均視為可比對範圍。');
    }
    if (!facts.hasKnownCurrency) {
      reasons.add('幣別未知，不自動補值或作為排除條件。');
    }

    final selectedMatch = selected == null
        ? null
        : matches.firstWhere((match) => identical(match.snapshot, selected));
    final accountPlan = selected == null
        ? _newDraftAccountPlan(facts, accounts)
        : CloudInvoiceAccountResolutionPlan(
            status: CloudInvoiceAccountResolutionStatus.preservedExisting,
            options: const <CloudInvoiceAccountSelectionOption>[],
            preservedAccountName: selected.transaction.accountName,
          );

    return CloudInvoiceReconciliationPlan(
      recommendedOutcome: outcome,
      rankedMatches: List<CloudInvoiceTransactionMatch>.unmodifiable(matches),
      allowedActions: _allowedActions(outcome, matches),
      merchantPlan: merchantPlan,
      accountPlan: accountPlan,
      fieldDifferences: _fieldDifferences(facts, selectedMatch),
      reasons: List<String>.unmodifiable(reasons),
    );
  }

  CloudInvoiceTransactionMatch _evaluate({
    required CloudInvoiceCandidateFacts facts,
    required LocalTransactionReconciliationSnapshot snapshot,
    required List<AccountRecord> accounts,
  }) {
    final candidate = facts.candidate;
    final transaction = snapshot.transaction;
    final signals = <CloudInvoiceMatchSignal>{
      CloudInvoiceMatchSignal.sameCalendarDate,
    };
    var score = 40;

    final exactAmount =
        (candidate.totalAmount - transaction.amount).abs() <= amountTolerance;
    if (exactAmount) {
      signals.add(CloudInvoiceMatchSignal.exactAmount);
      score += 30;
    } else {
      signals.add(CloudInvoiceMatchSignal.amountConflict);
    }

    final currencyConflict = facts.hasKnownCurrency &&
        _normalizeCode(facts.currencyCode!) !=
            _normalizeCode(transaction.currency.code);
    if (currencyConflict) {
      signals.add(CloudInvoiceMatchSignal.currencyConflict);
      score -= 100;
    }

    final merchantRelation = _merchantRelation(
      candidate.sellerName,
      transaction.merchantName,
    );
    switch (merchantRelation) {
      case _MerchantRelation.exact:
        signals.add(CloudInvoiceMatchSignal.merchantExact);
        score += 20;
      case _MerchantRelation.similar:
        signals.add(CloudInvoiceMatchSignal.merchantSimilar);
        score += 10;
      case _MerchantRelation.conflict:
        signals.add(CloudInvoiceMatchSignal.merchantConflict);
      case _MerchantRelation.unknown:
        break;
    }

    final hint = facts.paymentHint;
    if (_hasText(hint.accountName) &&
        _normalizeText(hint.accountName!) ==
            _normalizeText(transaction.accountName)) {
      signals.add(CloudInvoiceMatchSignal.accountNameMatch);
      score += 15;
    }

    final transactionAccount = _findAccount(transaction.accountName, accounts);
    if (hint.accountType != null &&
        transactionAccount?.type == hint.accountType) {
      signals.add(CloudInvoiceMatchSignal.accountTypeMatch);
      score += 10;
    }
    if (_hasText(hint.methodLabel) &&
        transactionAccount != null &&
        _paymentMethodMatches(hint.methodLabel!, transactionAccount)) {
      signals.add(CloudInvoiceMatchSignal.paymentMethodMatch);
      score += 10;
    }

    final invoiceIdentity = _invoiceIdentityMatches(candidate, snapshot);
    if (invoiceIdentity) {
      signals.add(CloudInvoiceMatchSignal.invoiceIdentity);
      score += 100;
    }

    final merchantEvidence =
        signals.contains(CloudInvoiceMatchSignal.merchantExact) ||
            signals.contains(CloudInvoiceMatchSignal.merchantSimilar);
    final paymentEvidence =
        signals.contains(CloudInvoiceMatchSignal.accountNameMatch) ||
            signals.contains(CloudInvoiceMatchSignal.accountTypeMatch) ||
            signals.contains(CloudInvoiceMatchSignal.paymentMethodMatch);

    final outcome = currencyConflict
        ? CloudInvoiceReconciliationOutcome.keepSeparate
        : invoiceIdentity && exactAmount
            ? CloudInvoiceReconciliationOutcome.exactDuplicate
            : exactAmount && (merchantEvidence || paymentEvidence)
                ? CloudInvoiceReconciliationOutcome.enrichExisting
                : exactAmount
                    ? CloudInvoiceReconciliationOutcome.ambiguous
                    : CloudInvoiceReconciliationOutcome.keepSeparate;

    final canOfferReplacement = !currencyConflict &&
        !exactAmount &&
        (invoiceIdentity ||
            signals.contains(CloudInvoiceMatchSignal.merchantExact) ||
            signals.contains(CloudInvoiceMatchSignal.accountNameMatch));

    return CloudInvoiceTransactionMatch(
      snapshot: snapshot,
      score: score,
      signals: Set<CloudInvoiceMatchSignal>.unmodifiable(signals),
      recommendedOutcome: outcome,
      canOfferReplacement: canOfferReplacement,
    );
  }

  CloudInvoiceMerchantResolutionPlan _resolveMerchant(
    CloudInvoiceCandidate candidate,
    List<MerchantRecord> merchants,
  ) {
    final sellerName = candidate.sellerName.trim();
    if (sellerName.isEmpty) {
      return const CloudInvoiceMerchantResolutionPlan(
        status: CloudInvoiceMerchantResolutionStatus.unresolved,
      );
    }

    final sellerKey = _normalizeText(sellerName);
    final matches = merchants
        .where((merchant) => !merchant.isArchived)
        .where(
          (merchant) =>
              _normalizeText(merchant.name) == sellerKey ||
              (_hasText(merchant.alias) &&
                  _normalizeText(merchant.alias) == sellerKey),
        )
        .toList();

    if (matches.length == 1) {
      return CloudInvoiceMerchantResolutionPlan(
        status: CloudInvoiceMerchantResolutionStatus.linkedExisting,
        existingMerchant: matches.single,
      );
    }
    if (matches.length > 1) {
      return const CloudInvoiceMerchantResolutionPlan(
        status: CloudInvoiceMerchantResolutionStatus.unresolved,
      );
    }
    return CloudInvoiceMerchantResolutionPlan(
      status: CloudInvoiceMerchantResolutionStatus.createDraftProposed,
      creationProposal: CloudInvoiceMerchantCreationProposal(
        name: sellerName,
        sellerIdentifier: candidate.sellerIdentifier.trim(),
        sourceInvoiceNumber: candidate.invoiceNumber.trim(),
      ),
    );
  }

  CloudInvoiceAccountResolutionPlan _newDraftAccountPlan(
    CloudInvoiceCandidateFacts facts,
    List<AccountRecord> accounts,
  ) {
    final active = accounts.where((account) => !account.isArchived).toList()
      ..sort((left, right) {
        final order = left.sortOrder.compareTo(right.sortOrder);
        return order != 0
            ? order
            : left.displayName.compareTo(right.displayName);
      });

    if (active.isEmpty) {
      return const CloudInvoiceAccountResolutionPlan(
        status: CloudInvoiceAccountResolutionStatus.newAccountRequired,
        options: <CloudInvoiceAccountSelectionOption>[],
      );
    }

    final options = active
        .map(
          (account) => CloudInvoiceAccountSelectionOption(
            account: account,
            currencyCompatible: !facts.hasKnownCurrency ||
                _normalizeCode(account.currency.code) ==
                    _normalizeCode(facts.currencyCode!),
            matchesHint: _accountMatchesHint(account, facts.paymentHint),
          ),
        )
        .toList();
    final hinted = options.where((option) => option.matchesHint).toList();

    return CloudInvoiceAccountResolutionPlan(
      status: CloudInvoiceAccountResolutionStatus.selectionRequired,
      options: List<CloudInvoiceAccountSelectionOption>.unmodifiable(options),
      suggestedAccountId:
          hinted.length == 1 ? hinted.single.account.id : null,
    );
  }

  List<CloudInvoiceFieldDifference> _fieldDifferences(
    CloudInvoiceCandidateFacts facts,
    CloudInvoiceTransactionMatch? match,
  ) {
    final candidate = facts.candidate;
    final snapshot = match?.snapshot;
    final transaction = snapshot?.transaction;
    final existingInvoice = snapshot?.invoiceNumber;
    final existingSeller = snapshot?.sellerIdentifier;

    return <CloudInvoiceFieldDifference>[
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.invoiceNumber,
        existingValue: existingInvoice,
        candidateValue: candidate.invoiceNumber,
        isMaterialConflict: _hasText(existingInvoice) &&
            _normalizeCode(existingInvoice!) !=
                _normalizeCode(candidate.invoiceNumber),
        isSafeEnrichment: !_hasText(existingInvoice),
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.sellerIdentifier,
        existingValue: existingSeller,
        candidateValue: candidate.sellerIdentifier,
        isMaterialConflict: _hasText(existingSeller) &&
            _hasText(candidate.sellerIdentifier) &&
            _normalizeCode(existingSeller!) !=
                _normalizeCode(candidate.sellerIdentifier),
        isSafeEnrichment:
            !_hasText(existingSeller) && _hasText(candidate.sellerIdentifier),
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.merchantName,
        existingValue: transaction?.merchantName,
        candidateValue: candidate.sellerName,
        isMaterialConflict: transaction != null &&
            _hasText(transaction.merchantName) &&
            _hasText(candidate.sellerName) &&
            _merchantRelation(transaction.merchantName, candidate.sellerName) ==
                _MerchantRelation.conflict,
        isSafeEnrichment: transaction != null &&
            !_hasText(transaction.merchantName) &&
            _hasText(candidate.sellerName),
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.amount,
        existingValue: transaction?.amount.toString(),
        candidateValue: candidate.totalAmount.toString(),
        isMaterialConflict: transaction != null &&
            (transaction.amount - candidate.totalAmount).abs() > amountTolerance,
        isSafeEnrichment: false,
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.transactionDate,
        existingValue:
            transaction == null ? null : _dateKey(transaction.occurredAt),
        candidateValue: _dateKey(candidate.invoiceDate),
        isMaterialConflict: transaction != null &&
            !_sameDate(transaction.occurredAt, candidate.invoiceDate),
        isSafeEnrichment: false,
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.exactTime,
        existingValue: transaction?.occurredAt.toIso8601String(),
        candidateValue: facts.hasExactTime
            ? candidate.invoiceDate.toIso8601String()
            : null,
        isMaterialConflict: false,
        isSafeEnrichment: transaction != null && facts.hasExactTime,
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.currency,
        existingValue: transaction?.currency.code,
        candidateValue: facts.currencyCode,
        isMaterialConflict: transaction != null &&
            facts.hasKnownCurrency &&
            _normalizeCode(transaction.currency.code) !=
                _normalizeCode(facts.currencyCode!),
        isSafeEnrichment: false,
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.taxAmount,
        existingValue: null,
        candidateValue: candidate.taxAmount?.toString(),
        isMaterialConflict: false,
        isSafeEnrichment: candidate.taxAmount != null,
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.lineItems,
        existingValue: null,
        candidateValue: candidate.lineItems.isEmpty
            ? null
            : candidate.lineItems.length.toString(),
        isMaterialConflict: false,
        isSafeEnrichment: candidate.lineItems.isNotEmpty,
      ),
      CloudInvoiceFieldDifference(
        field: CloudInvoiceReconciliationField.account,
        existingValue: transaction?.accountName,
        candidateValue: facts.paymentHint.accountName,
        isMaterialConflict: transaction != null &&
            _hasText(facts.paymentHint.accountName) &&
            _normalizeText(transaction.accountName) !=
                _normalizeText(facts.paymentHint.accountName!),
        isSafeEnrichment: false,
      ),
    ];
  }

  Set<CloudInvoiceReconciliationOutcome> _allowedActions(
    CloudInvoiceReconciliationOutcome outcome,
    List<CloudInvoiceTransactionMatch> matches,
  ) {
    final replacement = matches.any((match) => match.canOfferReplacement);
    switch (outcome) {
      case CloudInvoiceReconciliationOutcome.exactDuplicate:
        return const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.exactDuplicate,
          CloudInvoiceReconciliationOutcome.keepSeparate,
        };
      case CloudInvoiceReconciliationOutcome.enrichExisting:
        return <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.enrichExisting,
          CloudInvoiceReconciliationOutcome.keepSeparate,
          if (replacement) CloudInvoiceReconciliationOutcome.replaceExisting,
        };
      case CloudInvoiceReconciliationOutcome.keepSeparate:
      case CloudInvoiceReconciliationOutcome.ambiguous:
        return <CloudInvoiceReconciliationOutcome>{
          outcome,
          CloudInvoiceReconciliationOutcome.keepSeparate,
          CloudInvoiceReconciliationOutcome.createNewDraft,
          if (replacement) CloudInvoiceReconciliationOutcome.replaceExisting,
        };
      case CloudInvoiceReconciliationOutcome.createNewDraft:
        return const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        };
      case CloudInvoiceReconciliationOutcome.replaceExisting:
        return const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.replaceExisting,
          CloudInvoiceReconciliationOutcome.keepSeparate,
        };
      case CloudInvoiceReconciliationOutcome.blocked:
        return const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.blocked,
        };
    }
  }

  bool _isBlocked(CloudInvoiceCandidate candidate) {
    return candidate.totalAmount <= 0 ||
        candidate.status == CloudInvoiceCandidateStatus.blocked ||
        candidate.status == CloudInvoiceCandidateStatus.rejected ||
        candidate.hasError;
  }

  bool _invoiceIdentityMatches(
    CloudInvoiceCandidate candidate,
    LocalTransactionReconciliationSnapshot snapshot,
  ) {
    if (!_hasText(candidate.invoiceNumber) ||
        !_hasText(snapshot.invoiceNumber)) {
      return false;
    }
    if (_normalizeCode(candidate.invoiceNumber) !=
        _normalizeCode(snapshot.invoiceNumber!)) {
      return false;
    }
    if (_hasText(candidate.sellerIdentifier) &&
        _hasText(snapshot.sellerIdentifier) &&
        _normalizeCode(candidate.sellerIdentifier) !=
            _normalizeCode(snapshot.sellerIdentifier!)) {
      return false;
    }
    return true;
  }

  _MerchantRelation _merchantRelation(String left, String right) {
    if (!_hasText(left) || !_hasText(right)) return _MerchantRelation.unknown;
    final leftKey = _normalizeText(left);
    final rightKey = _normalizeText(right);
    if (leftKey == rightKey) return _MerchantRelation.exact;
    if (leftKey.length >= 4 &&
        rightKey.length >= 4 &&
        (leftKey.contains(rightKey) || rightKey.contains(leftKey))) {
      return _MerchantRelation.similar;
    }
    return _MerchantRelation.conflict;
  }

  bool _accountMatchesHint(
    AccountRecord account,
    CloudInvoicePaymentHint hint,
  ) {
    if (_hasText(hint.accountName) &&
        (_normalizeText(account.name) == _normalizeText(hint.accountName!) ||
            _normalizeText(account.displayName) ==
                _normalizeText(hint.accountName!))) {
      return true;
    }
    if (hint.accountType != null && account.type == hint.accountType) {
      return true;
    }
    return _hasText(hint.methodLabel) &&
        _paymentMethodMatches(hint.methodLabel!, account);
  }

  bool _paymentMethodMatches(String label, AccountRecord account) {
    final key = _normalizeText(label);
    return key == _normalizeText(account.type.label) ||
        key == _normalizeText(account.type.name) ||
        key == _normalizeText(account.name) ||
        key == _normalizeText(account.displayName);
  }

  AccountRecord? _findAccount(String accountName, List<AccountRecord> accounts) {
    final key = _normalizeText(accountName);
    for (final account in accounts) {
      if (_normalizeText(account.name) == key ||
          _normalizeText(account.displayName) == key) {
        return account;
      }
    }
    return null;
  }

  int _compareMatches(
    CloudInvoiceTransactionMatch left,
    CloudInvoiceTransactionMatch right,
  ) {
    final byScore = right.score.compareTo(left.score);
    return byScore != 0
        ? byScore
        : left.snapshot.transaction.id
            .compareTo(right.snapshot.transaction.id);
  }

  bool _sameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _dateKey(DateTime value) {
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }

  String _normalizeCode(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  String _normalizeText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_.，。、／/()（）]'), '');

  bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

enum _MerchantRelation {
  unknown,
  exact,
  similar,
  conflict,
}
