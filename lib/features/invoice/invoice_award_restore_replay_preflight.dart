/// Isolated V25-B restore-replay decision. No production activation or writes.
///
/// The trusted revision floor must come from a separately authenticated,
/// non-restorable authority. A value read from the restored database itself
/// cannot be used as that floor.
class InvoiceAwardRestoreReplayPreflight {
  const InvoiceAwardRestoreReplayPreflight();

  /// Fail closed when an independently authenticated floor is absent.
  ///
  /// Equality is allowed only for a snapshot already attested as current.
  /// This comparison is a candidate test, not an authorization to post.
  bool isCandidateCurrent({
    required int? restoredRevision,
    required int? trustedRevisionFloor,
    required bool independentlyAttested,
  }) {
    if (!independentlyAttested ||
        restoredRevision == null ||
        trustedRevisionFloor == null ||
        restoredRevision < 0 ||
        trustedRevisionFloor < 0) {
      return false;
    }
    return restoredRevision == trustedRevisionFloor;
  }

  /// A stale or future revision cannot become trusted merely by restoring it.
  /// Formal activation stays blocked until durable custody is integrated.
  bool canActivateProduction() => false;
}
