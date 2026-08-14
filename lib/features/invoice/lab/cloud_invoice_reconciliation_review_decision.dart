import 'package:flutter/foundation.dart';

import 'cloud_invoice_reconciliation_models.dart';

enum CloudInvoiceMerchantProposalChoice {
  createMerchant,
  skipMerchant,
}

class CloudInvoiceReconciliationReviewDecision {
  const CloudInvoiceReconciliationReviewDecision({
    required this.action,
    required this.selectedTransactionId,
    required this.selectedAccountId,
    required this.merchantProposalReviewed,
    required this.merchantProposalConfirmed,
    required this.replacementSecondConfirmationCompleted,
    required this.candidateReference,
    required this.decidedAt,
  });

  final CloudInvoiceReconciliationOutcome action;
  final String? selectedTransactionId;
  final String? selectedAccountId;
  final bool merchantProposalReviewed;
  final bool merchantProposalConfirmed;
  final bool replacementSecondConfirmationCompleted;
  final String candidateReference;
  final DateTime decidedAt;

  bool get canWriteFormalTransactionAutomatically => false;
  bool get canPersistMerchantAutomatically => false;
  bool get canPersistAccountAutomatically => false;
  bool get canReplaceAutomatically => false;
}

class CloudInvoiceReconciliationReviewController extends ChangeNotifier {
  CloudInvoiceReconciliationReviewController({
    required this.facts,
    required this.plan,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CloudInvoiceCandidateFacts facts;
  final CloudInvoiceReconciliationPlan plan;
  final DateTime Function() _now;

  CloudInvoiceReconciliationOutcome? _selectedAction;
  String? _selectedTransactionId;
  String? _selectedAccountId;
  CloudInvoiceMerchantProposalChoice? _merchantProposalChoice;
  bool _replacementConfirmed = false;

  CloudInvoiceReconciliationOutcome? get selectedAction => _selectedAction;
  String? get selectedTransactionId => _selectedTransactionId;
  String? get selectedAccountId => _selectedAccountId;
  CloudInvoiceMerchantProposalChoice? get merchantProposalChoice =>
      _merchantProposalChoice;
  bool get replacementConfirmed => _replacementConfirmed;

  bool get isBlocked =>
      plan.recommendedOutcome == CloudInvoiceReconciliationOutcome.blocked;

  CloudInvoiceTransactionMatch? get selectedMatch {
    final selectedId = _selectedTransactionId;
    if (selectedId == null) return null;
    for (final match in plan.rankedMatches) {
      if (match.snapshot.transaction.id == selectedId) return match;
    }
    return null;
  }

  Set<CloudInvoiceReconciliationOutcome> get availableActions {
    if (isBlocked) return const <CloudInvoiceReconciliationOutcome>{};
    final actions = plan.allowedActions
        .where(_isCommitLikeAction)
        .toSet();
    final match = selectedMatch;
    if (plan.recommendedOutcome == CloudInvoiceReconciliationOutcome.ambiguous &&
        match != null &&
        (match.recommendedOutcome ==
                CloudInvoiceReconciliationOutcome.enrichExisting ||
            match.recommendedOutcome ==
                CloudInvoiceReconciliationOutcome.exactDuplicate)) {
      actions.add(match.recommendedOutcome);
    }
    return Set<CloudInvoiceReconciliationOutcome>.unmodifiable(actions);
  }

  bool get requiresExplicitMatchSelection {
    if (_selectedAction == null || !_actionUsesExistingTransaction) {
      return false;
    }
    return plan.rankedMatches.length != 1;
  }

  bool get requiresAccountSelection =>
      _selectedAction == CloudInvoiceReconciliationOutcome.createNewDraft &&
      plan.accountPlan.requiresUserSelection;

  bool get requiresNewAccount =>
      _selectedAction == CloudInvoiceReconciliationOutcome.createNewDraft &&
      plan.accountPlan.requiresNewAccount;

  bool get requiresMerchantProposalDecision {
    if (plan.merchantPlan.status !=
        CloudInvoiceMerchantResolutionStatus.createDraftProposed) {
      return false;
    }
    return _selectedAction == CloudInvoiceReconciliationOutcome.createNewDraft ||
        _selectedAction == CloudInvoiceReconciliationOutcome.enrichExisting ||
        _selectedAction == CloudInvoiceReconciliationOutcome.replaceExisting;
  }

  bool get requiresReplacementConfirmation =>
      _selectedAction == CloudInvoiceReconciliationOutcome.replaceExisting;

  String? get resolvedTransactionId {
    if (!_actionUsesExistingTransaction) return null;
    final selected = _selectedTransactionId;
    if (selected != null) return selected;
    if (plan.rankedMatches.length == 1) {
      return plan.rankedMatches.single.snapshot.transaction.id;
    }
    return null;
  }

  bool get canSubmit {
    final action = _selectedAction;
    if (action == null || isBlocked || !availableActions.contains(action)) {
      return false;
    }
    if (_actionUsesExistingTransaction && resolvedTransactionId == null) {
      return false;
    }
    if (requiresAccountSelection && !_isValidSelectedAccount) {
      return false;
    }
    if (requiresNewAccount) return false;
    if (requiresMerchantProposalDecision && _merchantProposalChoice == null) {
      return false;
    }
    if (requiresReplacementConfirmation && !_replacementConfirmed) {
      return false;
    }
    return true;
  }

  void selectTransaction(String? transactionId) {
    if (transactionId != null &&
        !plan.rankedMatches.any(
          (match) => match.snapshot.transaction.id == transactionId,
        )) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'Unknown reconciliation match.',
      );
    }
    if (_selectedTransactionId == transactionId) return;
    _selectedTransactionId = transactionId;
    if (_selectedAction != null &&
        !availableActions.contains(_selectedAction)) {
      _selectedAction = null;
      _replacementConfirmed = false;
    }
    notifyListeners();
  }

  void selectAction(CloudInvoiceReconciliationOutcome? action) {
    if (action != null && !availableActions.contains(action)) {
      throw ArgumentError.value(
        action,
        'action',
        'The selected action is not allowed by the review plan.',
      );
    }
    if (_selectedAction == action) return;
    _selectedAction = action;
    if (action != CloudInvoiceReconciliationOutcome.createNewDraft) {
      _selectedAccountId = null;
    }
    if (action != CloudInvoiceReconciliationOutcome.replaceExisting) {
      _replacementConfirmed = false;
    }
    if (!requiresMerchantProposalDecision) {
      _merchantProposalChoice = null;
    }
    notifyListeners();
  }

  void selectAccount(String? accountId) {
    if (accountId != null) {
      final matches = plan.accountPlan.options.where(
        (option) => option.account.id == accountId,
      );
      if (matches.length != 1 || !matches.single.currencyCompatible) {
        throw ArgumentError.value(
          accountId,
          'accountId',
          'The account is unavailable or currency-incompatible.',
        );
      }
    }
    if (_selectedAccountId == accountId) return;
    _selectedAccountId = accountId;
    notifyListeners();
  }

  void chooseMerchantProposal(CloudInvoiceMerchantProposalChoice? choice) {
    if (plan.merchantPlan.status !=
        CloudInvoiceMerchantResolutionStatus.createDraftProposed) {
      throw StateError('MERCHANT_PROPOSAL_UNAVAILABLE');
    }
    if (_merchantProposalChoice == choice) return;
    _merchantProposalChoice = choice;
    notifyListeners();
  }

  void setReplacementConfirmed(bool value) {
    if (_selectedAction !=
        CloudInvoiceReconciliationOutcome.replaceExisting) {
      throw StateError('REPLACEMENT_ACTION_NOT_SELECTED');
    }
    if (_replacementConfirmed == value) return;
    _replacementConfirmed = value;
    notifyListeners();
  }

  CloudInvoiceReconciliationReviewDecision buildDecision() {
    if (!canSubmit) throw StateError('REVIEW_DECISION_INCOMPLETE');
    final action = _selectedAction!;
    return CloudInvoiceReconciliationReviewDecision(
      action: action,
      selectedTransactionId: resolvedTransactionId,
      selectedAccountId:
          action == CloudInvoiceReconciliationOutcome.createNewDraft
              ? _selectedAccountId
              : null,
      merchantProposalReviewed:
          !requiresMerchantProposalDecision || _merchantProposalChoice != null,
      merchantProposalConfirmed:
          _merchantProposalChoice ==
              CloudInvoiceMerchantProposalChoice.createMerchant,
      replacementSecondConfirmationCompleted:
          action == CloudInvoiceReconciliationOutcome.replaceExisting &&
              _replacementConfirmed,
      candidateReference: facts.candidate.duplicateKey,
      decidedAt: _now(),
    );
  }

  bool get _actionUsesExistingTransaction =>
      _selectedAction == CloudInvoiceReconciliationOutcome.exactDuplicate ||
      _selectedAction == CloudInvoiceReconciliationOutcome.enrichExisting ||
      _selectedAction == CloudInvoiceReconciliationOutcome.replaceExisting;

  bool get _isValidSelectedAccount {
    final selected = _selectedAccountId;
    if (selected == null) return false;
    return plan.accountPlan.options.any(
      (option) =>
          option.account.id == selected && option.currencyCompatible,
    );
  }

  bool _isCommitLikeAction(CloudInvoiceReconciliationOutcome action) {
    return action != CloudInvoiceReconciliationOutcome.ambiguous &&
        action != CloudInvoiceReconciliationOutcome.blocked;
  }
}
