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

  fun noteStart(startId: Int) { latestStartId.set(startId) }
  fun tryAcquire(): Boolean = active.compareAndSet(false, true)
  fun isActive(): Boolean = active.get()
  fun latestStartId(): Int = latestStartId.get()
  fun release() { active.set(false) }
}
