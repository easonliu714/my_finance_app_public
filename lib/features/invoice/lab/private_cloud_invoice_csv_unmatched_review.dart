import 'private_cloud_invoice_csv_reconciliation_preview.dart';

class PrivateCloudInvoiceCsvUnmatchedReview {
  PrivateCloudInvoiceCsvUnmatchedReview._({
    required this.items,
    required Set<String> selectedInvoiceIds,
    required Map<String, String> accountIdByInvoiceId,
  })  : selectedInvoiceIds = Set.unmodifiable(selectedInvoiceIds),
        accountIdByInvoiceId = Map.unmodifiable(accountIdByInvoiceId);

  factory PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(
    PrivateCloudInvoiceCsvReconciliationPreview preview,
  ) {
    final items = preview.items
        .where(
          (item) =>
              item.status ==
                  PrivateCloudInvoiceCsvReconciliationStatus.unmatched &&
              item.invoice.isSupported &&
              item.invoice.candidate != null,
        )
        .toList(growable: false);
    return PrivateCloudInvoiceCsvUnmatchedReview._(
      items: List.unmodifiable(items),
      selectedInvoiceIds: const <String>{},
      accountIdByInvoiceId: const <String, String>{},
    );
  }

  final List<PrivateCloudInvoiceCsvReconciliationItem> items;
  final Set<String> selectedInvoiceIds;
  final Map<String, String> accountIdByInvoiceId;

  bool get hasItems => items.isNotEmpty;
  int get selectedCount => selectedInvoiceIds.length;
  int get assignedSelectedCount => selectedInvoiceIds
      .where((invoiceId) => accountIdByInvoiceId.containsKey(invoiceId))
      .length;
  int get missingAccountCount => selectedCount - assignedSelectedCount;
  int get deferredCount => items.length - selectedCount;
  bool get canDeferMissingAccounts =>
      assignedSelectedCount > 0 && missingAccountCount > 0;
  bool get canSubmit => selectedCount > 0 && missingAccountCount == 0;

  bool isSelected(String invoiceId) => selectedInvoiceIds.contains(invoiceId);
  String? accountIdFor(String invoiceId) => accountIdByInvoiceId[invoiceId];

  PrivateCloudInvoiceCsvUnmatchedReview toggle(String invoiceId) {
    _requireInvoice(invoiceId);
    final next = Set<String>.from(selectedInvoiceIds);
    if (!next.add(invoiceId)) {
      next.remove(invoiceId);
    }
    return _copy(selectedInvoiceIds: next);
  }

  PrivateCloudInvoiceCsvUnmatchedReview selectAll() {
    return _copy(
      selectedInvoiceIds: items.map((item) => item.invoice.id).toSet(),
    );
  }

  PrivateCloudInvoiceCsvUnmatchedReview clearSelection() {
    return _copy(selectedInvoiceIds: const <String>{});
  }

  /// Keeps only selected invoices that already have an account assignment.
  ///
  /// This is an explicit partial-import action: invoices without an account are
  /// removed from the current submission selection and remain available for a
  /// later CSV review. The strict [canSubmit] invariant remains unchanged.
  PrivateCloudInvoiceCsvUnmatchedReview deferSelectedWithoutAccount() {
    if (missingAccountCount == 0) {
      return this;
    }
    final readyInvoiceIds = selectedInvoiceIds
        .where(accountIdByInvoiceId.containsKey)
        .toSet();
    return _copy(selectedInvoiceIds: readyInvoiceIds);
  }

  /// Assigns the account to every selected invoice, replacing prior choices.
  ///
  /// Callers must expose this as an explicit overwrite action because it can
  /// replace per-invoice account decisions.
  PrivateCloudInvoiceCsvUnmatchedReview assignSelected(String accountId) {
    if (accountId.trim().isEmpty) {
      throw StateError('ACCOUNT_REQUIRED');
    }
    final next = Map<String, String>.from(accountIdByInvoiceId);
    for (final invoiceId in selectedInvoiceIds) {
      next[invoiceId] = accountId;
    }
    return _copy(accountIdByInvoiceId: next);
  }

  /// Fills only selected invoices that do not yet have an account.
  ///
  /// This is the safe default for the lower bulk-action panel. Existing
  /// per-invoice overrides remain unchanged unless [assignSelected] is invoked
  /// through the explicit overwrite action.
  PrivateCloudInvoiceCsvUnmatchedReview assignSelectedMissing(String accountId) {
    if (accountId.trim().isEmpty) {
      throw StateError('ACCOUNT_REQUIRED');
    }
    final next = Map<String, String>.from(accountIdByInvoiceId);
    for (final invoiceId in selectedInvoiceIds) {
      next.putIfAbsent(invoiceId, () => accountId);
    }
    return _copy(accountIdByInvoiceId: next);
  }

  PrivateCloudInvoiceCsvUnmatchedReview assignInvoice({
    required String invoiceId,
    required String? accountId,
  }) {
    _requireInvoice(invoiceId);
    final next = Map<String, String>.from(accountIdByInvoiceId);
    if (accountId == null || accountId.trim().isEmpty) {
      next.remove(invoiceId);
    } else {
      next[invoiceId] = accountId;
    }
    return _copy(accountIdByInvoiceId: next);
  }

  Map<String, Set<String>> selectedInvoiceIdsByAccount() {
    if (!canSubmit) {
      throw StateError('SELECTED_INVOICES_REQUIRE_ACCOUNTS');
    }
    final result = <String, Set<String>>{};
    for (final invoiceId in selectedInvoiceIds) {
      final accountId = accountIdByInvoiceId[invoiceId]!;
      result.putIfAbsent(accountId, () => <String>{}).add(invoiceId);
    }
    return Map.unmodifiable(
      result.map(
        (accountId, invoiceIds) => MapEntry(
          accountId,
          Set<String>.unmodifiable(invoiceIds),
        ),
      ),
    );
  }

  void _requireInvoice(String invoiceId) {
    if (!items.any((item) => item.invoice.id == invoiceId)) {
      throw StateError('UNMATCHED_INVOICE_NOT_FOUND');
    }
  }

  PrivateCloudInvoiceCsvUnmatchedReview _copy({
    Set<String>? selectedInvoiceIds,
    Map<String, String>? accountIdByInvoiceId,
  }) {
    return PrivateCloudInvoiceCsvUnmatchedReview._(
      items: items,
      selectedInvoiceIds: selectedInvoiceIds ?? this.selectedInvoiceIds,
      accountIdByInvoiceId:
          accountIdByInvoiceId ?? this.accountIdByInvoiceId,
    );
  }
}
