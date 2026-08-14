import 'manual_invoice_draft.dart';

class ManualInvoiceDraftRepositoryError implements Exception {
  const ManualInvoiceDraftRepositoryError(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManualInvoiceDraftNotFoundError extends ManualInvoiceDraftRepositoryError {
  const ManualInvoiceDraftNotFoundError(super.message);
}

class ManualInvoiceDraftDuplicateError extends ManualInvoiceDraftRepositoryError {
  const ManualInvoiceDraftDuplicateError(super.message);
}

abstract interface class ManualInvoiceDraftRepository {
  Future<ManualInvoiceDraft> saveDraft(ManualInvoiceDraft draft);

  Future<ManualInvoiceDraft?> loadDraftById(String id);

  Future<ManualInvoiceDraft?> findDraftByDuplicateKey(String duplicateKey);

  Future<List<ManualInvoiceDraft>> loadDrafts({ManualInvoiceDraftStatus? status});

  Future<ManualInvoiceDraft> updateStatus({required String id, required ManualInvoiceDraftStatus status});

  Future<void> deleteDraft(String id);
}

class InMemoryManualInvoiceDraftRepository implements ManualInvoiceDraftRepository {
  InMemoryManualInvoiceDraftRepository({DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final Map<String, ManualInvoiceDraft> _draftsById = <String, ManualInvoiceDraft>{};

  @override
  Future<ManualInvoiceDraft> saveDraft(ManualInvoiceDraft draft) async {
    final existingDuplicate = await findDraftByDuplicateKey(draft.duplicateKey);
    if (existingDuplicate != null && existingDuplicate.id != draft.id && existingDuplicate.status != ManualInvoiceDraftStatus.rejected) {
      throw const ManualInvoiceDraftDuplicateError('Manual invoice draft already exists.');
    }

    final now = _clock();
    final existing = _draftsById[draft.id];
    final saved = draft.copyWith(
      createdAt: draft.createdAt ?? existing?.createdAt ?? now,
      updatedAt: now,
      status: draft.status,
    );
    _draftsById[saved.id] = saved;
    return saved;
  }

  @override
  Future<ManualInvoiceDraft?> loadDraftById(String id) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) return null;
    return _draftsById[trimmedId];
  }

  @override
  Future<ManualInvoiceDraft?> findDraftByDuplicateKey(String duplicateKey) async {
    final normalizedKey = duplicateKey.trim();
    if (normalizedKey.isEmpty) return null;
    for (final draft in _draftsById.values) {
      if (draft.duplicateKey == normalizedKey) return draft;
    }
    return null;
  }

  @override
  Future<List<ManualInvoiceDraft>> loadDrafts({ManualInvoiceDraftStatus? status}) async {
    final drafts = _draftsById.values.where((draft) => status == null || draft.status == status).toList();
    drafts.sort((a, b) {
      final bDate = b.updatedAt ?? b.createdAt ?? b.invoiceDate;
      final aDate = a.updatedAt ?? a.createdAt ?? a.invoiceDate;
      final updatedComparison = bDate.compareTo(aDate);
      if (updatedComparison != 0) return updatedComparison;
      return b.invoiceDate.compareTo(a.invoiceDate);
    });
    return List<ManualInvoiceDraft>.unmodifiable(drafts);
  }

  @override
  Future<ManualInvoiceDraft> updateStatus({required String id, required ManualInvoiceDraftStatus status}) async {
    final draft = await loadDraftById(id);
    if (draft == null) {
      throw const ManualInvoiceDraftNotFoundError('Manual invoice draft not found.');
    }
    return saveDraft(draft.copyWith(status: status));
  }

  @override
  Future<void> deleteDraft(String id) async {
    _draftsById.remove(id.trim());
  }
}
