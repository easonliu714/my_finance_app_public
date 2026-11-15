import 'invoice_award_revision_floor_custody.dart';

/// Isolated restore candidate: read an independently authenticated revision
/// floor at decision time. No database writes or production activation.
class InvoiceAwardRestoreFloorReadback {
  const InvoiceAwardRestoreFloorReadback();

  /// A restored snapshot must equal the current independent floor.
  /// Read failures, absent authority and races fail closed.
  Future<bool> isCandidateCurrent({
    required InvoiceAwardIndependentRevisionStore? store,
    required bool independentlyAuthenticated,
    required int? restoredRevision,
  }) async {
    if (!independentlyAuthenticated ||
        store == null ||
        restoredRevision == null ||
        restoredRevision < 0) {
      return false;
    }
    try {
      final first = await store.readFloor();
      if (first == null || first < 0 || first != restoredRevision) {
        return false;
      }
      // A second independent read catches observable floor movement.
      return await store.readFloor() == first;
    } catch (_) {
      return false;
    }
  }

  bool canActivateProduction() => false;
}
