/// Process-local mutual exclusion for Issue #13 official-award refreshes.
///
/// Manual refresh, foreground catch-up and the later Android scheduler must not
/// run overlapping authority pipelines against the same local repositories.
class InvoiceAwardRefreshProcessLease {
  const InvoiceAwardRefreshProcessLease._();

  static bool _active = false;

  static bool get isActive => _active;

  static bool tryAcquire() {
    if (_active) return false;
    _active = true;
    return true;
  }

  static void release() {
    _active = false;
  }
}
