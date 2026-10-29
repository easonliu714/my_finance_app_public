package me.movenext.flutter_pdf_text

import android.graphics.pdf.PdfRenderer
import io.legere.pdfiumandroid.PdfiumCore
import android.os.Debug
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * C500-G0d: API35, instrumentation-only official-file PdfRenderer preflight.
 * Source bytes arrive exclusively through a pinned, ephemeral GitHub lab.
 * This class does NOT run production award matching, write ledger/SQLite/LKG,
 * assert a global negative, or replace the installed Owner application.
 * Each real-file method runs in a separate instrumentation invocation.
 */
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 35)
class C500G0RendererLabInstrumentedTest {
  private val targetContext
    get() = InstrumentationRegistry.getInstrumentation().targetContext

  private fun labDirectory(): File =
    requireNotNull(targetContext.getExternalFilesDir("c500_g0_lab")) {
      "C500_G0D_EXTERNAL_PRIVATE_DIRECTORY_UNAVAILABLE"
    }

  private fun isPinned(file: File, expectedBytes: Long, expectedSha: String): Boolean {
    if (!file.isFile || file.length() != expectedBytes || file.isDirectory) return false
    val digest = MessageDigest.getInstance("SHA-256")
    FileInputStream(file).use { input ->
      val buffer = ByteArray(64 * 1024)
      while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (count > 0) digest.update(buffer, 0, count)
      }
    }
    val actual = digest.digest().joinToString("") {
      "%02x".format(it.toInt() and 0xff)
    }
    return actual.equals(expectedSha, ignoreCase = false)
  }

  private fun emit(period: String, stage: String, start: Long, extra: String = "", engine: String = "Android35_PdfRenderer") {
    val memory = Debug.MemoryInfo()
    Debug.getMemoryInfo(memory)
    val runtime = Runtime.getRuntime()
    val message = "period=" + period +
      " engine=" + engine + " stage=" + stage +
      " elapsed_ms=" + (SystemClock.elapsedRealtime() - start) +
      " java_used_bytes=" + (runtime.totalMemory() - runtime.freeMemory()) +
      " java_max_bytes=" + runtime.maxMemory() +
      " native_alloc_bytes=" + Debug.getNativeHeapAllocatedSize() +
      " process_pss_kb=" + memory.totalPss +
      " " + extra
    Log.i("C500_G0D", message)
    println("C500_G0D " + message)
  }

  @Test fun provisionAndRejectWrongSourceBeforeEngineOpen() {
    val dir = labDirectory()
    assertTrue("Lab directory creation", dir.isDirectory || dir.mkdirs())
    val fake = File(dir, "c500_g0_negative_synthetic.pdf")
    try {
      fake.writeText("%PDF-1.5\n%%EOF\n")
      assertFalse(
        "Synthetic or truncated source must fail closed before PdfRenderer",
        isPinned(fake, 119769589L,
          "1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe")
      )
    } finally {
      fake.delete()
    }
    assertNotNull("Lab path must be app-specific", targetContext.getExternalFilesDir("c500_g0_lab"))
  }

  @Test fun oldOfficialPdfRendererOpenAndBoundedPages() {
    inspect("115-05-06", "old.pdf", 119769589L,
      "1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe")
  }

  @Test fun newOfficialPdfRendererOpenAndBoundedPages() {
    inspect("115-07-08", "new.pdf", 135200798L,
      "f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571")
  }

  // C500-G0e: exact production PDFiumCore.newDocument API; separate invocation
  // per pinned official file. OPEN-ONLY, not page completeness or NOT_WIN proof.
  @Test fun oldOfficialPdfiumOpenOnly() {
    inspectPdfiumOpen("115-05-06", "old.pdf", 119769589L,
      "1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe")
  }

  @Test fun newOfficialPdfiumOpenOnly() {
    inspectPdfiumOpen("115-07-08", "new.pdf", 135200798L,
      "f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571")
  }

  private fun inspect(period: String, name: String, size: Long, sha: String) {
    val started = SystemClock.elapsedRealtime()
    val source = File(labDirectory(), name)
    emit(period, "SOURCE_SHA256_BEGIN", started, "expected_bytes=" + size)
    assertTrue("C500_G0D_PINNED_BINARY_MISSING_OR_MISMATCH_" + period,
      isPinned(source, size, sha))
    emit(period, "SOURCE_SHA256_OK", started)
    var descriptor: ParcelFileDescriptor? = null
    var renderer: PdfRenderer? = null
    try {
      emit(period, "OPEN_BEGIN", started)
      descriptor = ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
      renderer = PdfRenderer(descriptor)
      descriptor = null
      val count = renderer.pageCount
      assertTrue("C500_G0D_PAGE_COUNT_INVALID", count > 0)
      emit(period, "OPEN_OK", started, "page_count=" + count)
      // At most three pages. A sample is NOT full-file integrity or NOT_WIN proof.
      for (index in listOf(0, count / 2, count - 1).distinct()) {
        emit(period, "PAGE_BEGIN", started, "page_index=" + index)
        val page = renderer.openPage(index)
        try {
          val textItems = page.textContents.size
          emit(period, "PAGE_OK", started,
            "page_index=" + index + " text_item_count=" + textItems)
        } finally {
          page.close()
        }
      }
      emit(period, "SAMPLE_ONLY_PASS_NOT_GLOBAL_NEGATIVE", started)
    } catch (failure: Throwable) {
      emit(period, "ENGINE_FAILED", started,
        "failure_class=" + failure.javaClass.simpleName)
      throw failure
    } finally {
      try { renderer?.close() } catch (_: Throwable) {}
      try { descriptor?.close() } catch (_: Throwable) {}
    }
  }

  // Lab-only and bounded: PDFium is invoked once per fresh instrumentation
  // process. A native SIGSEGV may bypass Throwable; the host captures the
  // instrumentation exit and crash log, then independently runs the next file.
  private fun inspectPdfiumOpen(period: String, name: String, size: Long, sha: String) {
    val started = SystemClock.elapsedRealtime()
    val engine = "Android35_PdfiumCore_1.0.35"
    val source = File(labDirectory(), name)
    emit(period, "SOURCE_SHA256_BEGIN", started, "expected_bytes=" + size, engine)
    assertTrue("C500_G0E_PINNED_BINARY_MISSING_OR_MISMATCH_" + period,
      isPinned(source, size, sha))
    emit(period, "SOURCE_SHA256_OK", started, engine = engine)
    var descriptor: ParcelFileDescriptor? = null
    try {
      emit(period, "OPEN_BEGIN", started, engine = engine)
      descriptor = ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
      val document = PdfiumCore(targetContext).newDocument(descriptor)
      descriptor = null // ownership transferred only after successful open
      document.use {
        val pageCount = it.getPageCount()
        assertTrue("C500_G0E_PAGE_COUNT_INVALID", pageCount > 0)
        emit(period, "OPEN_OK", started, "page_count=" + pageCount, engine)
      }
      emit(period, "OPEN_ONLY_PASS_NOT_GLOBAL_NEGATIVE", started, engine = engine)
    } catch (failure: Throwable) {
      emit(period, "ENGINE_FAILED", started,
        "failure_class=" + failure.javaClass.simpleName, engine)
      throw failure
    } finally {
      try { descriptor?.close() } catch (_: Throwable) {}
    }
  }

}
