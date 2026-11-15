/// Candidate-only custody contract. The store MUST be authenticated and
/// outside every application database/backup/restore domain. No production
/// implementation is provided by this file.
abstract class InvoiceAwardIndependentRevisionStore {
  Future<int?> readFloor();
  Future<bool> compareAndAdvance(int expectedFloor, int nextFloor);
}

/// Isolated V25-B monotonic revision-floor protocol. It cannot authorize
/// production posting, and never treats a restored SQLite value as authority.
class InvoiceAwardRevisionFloorCustody {
  const InvoiceAwardRevisionFloorCustody();

  /// Fail closed on absent custody, exceptions, stale reads and CAS races.
  /// Caller must independently establish store provenance before using it.
  Future<bool> advanceCandidate({
    required InvoiceAwardIndependentRevisionStore? store,
    required bool independentlyAuthenticated,
    required int expectedFloor,
    required int nextFloor,
  }) async {
    if (!independentlyAuthenticated ||
        store == null ||
        expectedFloor < 0 ||
        nextFloor <= expectedFloor) {
      return false;
    }
    try {
      final observed = await store.readFloor();
      if (observed != expectedFloor) return false;
      if (!await store.compareAndAdvance(expectedFloor, nextFloor)) {
        return false;
      }
      // A successful write acknowledgement alone is insufficient.
      return await store.readFloor() == nextFloor;
    } catch (_) {
      return false;
    }
  }

  /// Never permit formal activation based on this isolated protocol.
  bool canActivateProduction() => false;
}
