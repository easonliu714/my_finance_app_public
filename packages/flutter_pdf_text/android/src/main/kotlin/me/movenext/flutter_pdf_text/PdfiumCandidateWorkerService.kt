package me.movenext.flutter_pdf_text

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.ParcelFileDescriptor
import io.legere.pdfiumandroid.PdfiumCore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * Crash-isolated candidate lookup for very large sorted MOF cloud-award PDFs.
 *
 * This service is declared in a dedicated Android process. The main Flutter
 * process sends only a local validated PDF path plus the local candidate
 * invoice-number universe. No invoice/accounting data leaves the device.
 * Results are written atomically to app-private storage; a partial/crashed
 * worker never creates a completed authority result.
 */
class PdfiumCandidateWorkerService : Service() {
  companion object {
    const val EXTRA_PDF_PATH = "pdf_path"
    const val EXTRA_CANDIDATES_JSON = "candidates_json"
    const val EXTRA_RESULT_PATH = "result_path"
    const val EXTRA_REQUEST_ID = "request_id"
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent == null) {
      stopSelf(startId)
      return START_NOT_STICKY
    }
    val pdfPath = intent.getStringExtra(EXTRA_PDF_PATH).orEmpty()
    val candidatesJson = intent.getStringExtra(EXTRA_CANDIDATES_JSON).orEmpty()
    val resultPath = intent.getStringExtra(EXTRA_RESULT_PATH).orEmpty()
    val requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
    thread(start = true, name = "issue13-pdfium-worker") {
      try {
        runLookup(pdfPath, candidatesJson, resultPath, requestId)
      } catch (oom: OutOfMemoryError) {
        writeFailure(resultPath, requestId, "PDFIUM_WORKER_OOM")
      } catch (error: Throwable) {
        writeFailure(
          resultPath,
          requestId,
          "PDFIUM_WORKER_FAILED:${error.javaClass.simpleName}"
        )
      } finally {
        stopSelf(startId)
      }
    }
    return START_NOT_STICKY
  }

  private fun runLookup(
    pdfPath: String,
    candidatesJson: String,
    resultPath: String,
    requestId: String
  ) {
    require(pdfPath.isNotBlank() && resultPath.isNotBlank() && requestId.isNotBlank())
    val source = File(pdfPath)
    require(source.isFile)
    val raw = JSONArray(candidatesJson)
    val candidates = (0 until raw.length())
      .map { raw.getString(it).replace(Regex("[\\s-]"), "").uppercase() }
      .filter { Regex("^[A-Z]{2}[0-9]{8}$").matches(it) }
      .distinct()
      .sorted()
    require(candidates.size == raw.length())

    var descriptor: ParcelFileDescriptor? = null
    var document: io.legere.pdfiumandroid.PdfDocument? = null
    try {
      descriptor = ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
      val core = PdfiumCore(applicationContext)
      document = core.newDocument(descriptor)
      descriptor = null // PdfDocument owns it after successful open.
      val pageCount = document.getPageCount()
      require(pageCount > 0)
      val matched = linkedSetOf<String>()
      val pagesRead = linkedSetOf<Int>()

      fun pageTokens(pageNumber: Int): List<String> {
        require(pageNumber in 1..pageCount)
        val page = document.openPage(pageNumber - 1)
        page.use {
          val textPage = page.openTextPage()
          textPage.use {
            val count = textPage.textPageCountChars()
            val text = if (count <= 0) "" else textPage.textPageGetText(0, count).orEmpty()
            pagesRead.add(pageNumber)
            return extractInvoiceNumbers(text)
          }
        }
      }

      candidates.forEach { candidate ->
        var low = 1
        var high = pageCount
        var found = false
        while (low <= high) {
          val middle = low + ((high - low) ushr 1)
          val tokens = pageTokens(middle)
          require(tokens.isNotEmpty())
          when {
            candidate < tokens.first() -> high = middle - 1
            candidate > tokens.last() -> low = middle + 1
            else -> {
              if (tokens.contains(candidate)) {
                matched.add(candidate)
                found = true
              } else {
                listOf(middle - 1, middle + 1)
                  .filter { it in 1..pageCount }
                  .forEach { neighbor ->
                    if (!found && pageTokens(neighbor).contains(candidate)) {
                      matched.add(candidate)
                      found = true
                    }
                  }
              }
              break
            }
          }
        }
        if (!found && low > high) {
          setOf(low, high)
            .filter { it in 1..pageCount }
            .forEach { boundary ->
              if (!found && pageTokens(boundary).contains(candidate)) {
                matched.add(candidate)
                found = true
              }
            }
        }
      }

      val payload = JSONObject()
        .put("request_id", requestId)
        .put("status", "complete")
        .put("page_count", pageCount)
        .put("pages_read", pagesRead.size)
        .put("candidate_count", candidates.size)
        .put("matched", JSONArray(matched.toList()))
      writeAtomic(resultPath, payload.toString())
    } finally {
      try { document?.close() } catch (_: Throwable) {}
      try { descriptor?.close() } catch (_: Throwable) {}
    }
  }

  private fun extractInvoiceNumbers(text: String): List<String> {
    val normalized = text.uppercase()
    val pattern = Regex("[A-Z]\\s*[A-Z](?:\\s*[0-9]){8}")
    return pattern.findAll(normalized).mapNotNull { match ->
      val before = normalized.getOrNull(match.range.first - 1)
      val after = normalized.getOrNull(match.range.last + 1)
      if ((before != null && before.isLetterOrDigit()) ||
          (after != null && after.isLetterOrDigit())) {
        null
      } else {
        match.value.replace(Regex("\\s+"), "")
          .takeIf { Regex("^[A-Z]{2}[0-9]{8}$").matches(it) }
      }
    }.distinct().sorted().toList()
  }

  private fun writeFailure(resultPath: String, requestId: String, code: String) {
    if (resultPath.isBlank() || requestId.isBlank()) return
    try {
      val payload = JSONObject()
        .put("request_id", requestId)
        .put("status", "failed")
        .put("error", code)
      writeAtomic(resultPath, payload.toString())
    } catch (_: Throwable) {
      // A worker killed by the OS may leave no result at all; the caller must
      // treat absence as interrupted and never promote partial authority.
    }
  }

  private fun writeAtomic(path: String, content: String) {
    val target = File(path)
    target.parentFile?.mkdirs()
    val temp = File(target.parentFile, target.name + ".tmp")
    temp.writeText(content)
    if (!temp.renameTo(target)) {
      target.writeText(content)
      temp.delete()
    }
  }
}
