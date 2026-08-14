import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the display awake only during an explicitly confirmed official-detail
/// operation. This is a screen wakelock only; it does not keep the process alive
/// or make background WebView execution reliable.
class OfficialInvoiceDetailScreenAwakeGuard {
  bool _acquired = false;

  Future<void> acquire() async {
    if (_acquired) return;
    try {
      await WakelockPlus.enable();
      _acquired = true;
    } catch (_) {
      // Best effort. Lifecycle-aware timeout suspension still protects the
      // current in-memory queue if the platform rejects the display lock.
    }
  }

  Future<void> release() async {
    if (!_acquired) return;
    _acquired = false;
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Releasing a best-effort display lock must not convert a completed
      // official-detail result into an application failure.
    }
  }
}
