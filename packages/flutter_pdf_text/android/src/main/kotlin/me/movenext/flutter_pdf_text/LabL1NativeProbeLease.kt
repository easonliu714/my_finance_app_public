package me.movenext.flutter_pdf_text

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Lab-only single-flight custody for the isolated PdfRenderer worker.
 * A rejected service start still advances Android's start ID; it must
 * never open a second renderer or release the incumbent worker.
 */
internal class LabL1NativeProbeLease {
  private val active = AtomicBoolean(false)
  private val latestStartId = AtomicInteger(0)

  @Synchronized fun noteStart(startId: Int) { latestStartId.set(startId) }
  @Synchronized fun tryAcquire(): Boolean = active.compareAndSet(false, true)
  @Synchronized fun isActive(): Boolean = active.get()
  @Synchronized fun latestStartId(): Int = latestStartId.get()
  @Synchronized fun release() { active.set(false) }

  // Called only after renderer and heartbeat cleanup. Keep admission
  // excluded until the old lease is released and its receipt published.
  // This is service-local custody, not proof of OS process exit.
  @Synchronized
  fun finish(stop: (Int) -> Unit, publishTerminal: () -> Unit) {
    check(active.get()) { "L1_NATIVE_LEASE_NOT_ACTIVE" }
    try {
      stop(latestStartId.get())
    } finally {
      active.set(false)
    }
    publishTerminal()
  }
}
