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
 * Crash-isolated exact-candidate lookup for very large sorted MOF cloud-award
 * PDFs. The service runs in a dedicated Android process with a fresh heap.
 *
 * This worker deliberately uses native PDFium rather than PDFBox. PDFBox's
 * PDDocument.load materializes the whole document object graph and exhausted
 * the worker heap on the 115-07-08 cloud-500 PDF. PDFium keeps the validated
 * file random-access and this worker opens/extracts only pages reached by the
 * bounded binary search for the exact on-device candidate universe.
 * No invoice/accounting data leaves the device.
 */
class PdfiumCandidateWorkerService : Service() {
  companion object {
    const val EXTRA_PDF_PATH = "pdf_path"
    const val EXTRA_CANDIDATES_JSON = "candidates_json"
    const val EXTRA_RESULT_PATH = "result_path"
    const val EXTRA_REQUEST_ID = "request_id"
  }

  private lateinit var pdfiumCore: PdfiumCore

  override fun onCreate() {
    super.onCreate()
    pdfiumCore = PdfiumCore(applicationContext)
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
    thread(start = true, name = "issue13-cloud500-worker") {
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

    writeRunning(
      resultPath = resultPath,
      requestId = requestId,
      stage = "PDFIUM_OPEN_BEGIN",
      candidateIndex = 0,
      candidateCount = candidates.size
    )

    var descriptor: ParcelFileDescriptor? = null
    try {
      descriptor = ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
      val document = pdfiumCore.newDocument(descriptor)
      descriptor = null // ownership transferred to PdfDocument
      document.use {
        val pageCount = document.getPageCount()
        require(pageCount > 0)
        val matched = linkedSetOf<String>()
        val pagesRead = linkedSetOf<Int>()

        writeRunning(
          resultPath = resultPath,
          requestId = requestId,
          stage = "PDFIUM_OPEN_OK",
          candidateIndex = 0,
          candidateCount = candidates.size,
          pageCount = pageCount
        )

        fun pageTokens(pageNumber: Int, candidateIndex: Int): List<String> {
          require(pageNumber in 1..pageCount)
          writeRunning(
            resultPath = resultPath,
            requestId = requestId,
            stage = "PDFIUM_PAGE_BEGIN",
            candidateIndex = candidateIndex,
            candidateCount = candidates.size,
            pageNumber = pageNumber,
            pageCount = pageCount,
            pagesRead = pagesRead.size
          )
          val page = document.openPage(pageNumber - 1)
          val text = page.use {
            val textPage = page.openTextPage()
            textPage.use {
              val count = textPage.textPageCountChars()
              if (count <= 0) "" else textPage.textPageGetText(0, count).orEmpty()
            }
          }
          pagesRead.add(pageNumber)
          writeRunning(
            resultPath = resultPath,
            requestId = requestId,
            stage = "PDFIUM_CANDIDATE_SEARCH",
            candidateIndex = candidateIndex,
            candidateCount = candidates.size,
            pageNumber = pageNumber,
            pageCount = pageCount,
            pagesRead = pagesRead.size
          )
          return extractInvoiceNumbers(text)
        }

        candidates.forEachIndexed { index, candidate ->
          var low = 1
          var high = pageCount
          var found = false
          while (low <= high) {
            val middle = low + ((high - low) ushr 1)
            val tokens = pageTokens(middle, index + 1)
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
                      if (!found && pageTokens(neighbor, index + 1).contains(candidate)) {
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
                if (!found && pageTokens(boundary, index + 1).contains(candidate)) {
                  matched.add(candidate)
                  found = true
                }
              }
          }
        }

        val payload = JSONObject()
          .put("request_id", requestId)
          .put("status", "complete")
          .put("engine", "pdfium-random-access-candidate-search")
          .put("stage", "PDFIUM_COMPLETE")
          .put("page_count", pageCount)
          .put("pages_read", pagesRead.size)
          .put("candidate_count", candidates.size)
          .put("matched", JSONArray(matched.toList()))
        writeAtomic(resultPath, payload.toString())
      }
    } finally {
      try { descriptor?.close() } catch (_: Exception) {}
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

  private fun writeRunning(
    resultPath: String,
    requestId: String,
    stage: String,
    candidateIndex: Int,
    candidateCount: Int,
    pageNumber: Int = 0,
    pageCount: Int = 0,
    pagesRead: Int = 0
  ) {
    val payload = JSONObject()
      .put("request_id", requestId)
      .put("status", "running")
      .put("engine", "pdfium-random-access-candidate-search")
      .put("stage", stage)
      .put("candidate_index", candidateIndex)
      .put("candidate_count", candidateCount)
      .put("page_number", pageNumber)
      .put("page_count", pageCount)
      .put("pages_read", pagesRead)
      .put("updated_at_ms", System.currentTimeMillis())
    writeAtomic(resultPath, payload.toString())
  }

  private fun writeFailure(resultPath: String, requestId: String, code: String) {
    if (resultPath.isBlank() || requestId.isBlank()) return
    try {
      val payload = JSONObject()
        .put("request_id", requestId)
        .put("status", "failed")
        .put("engine", "pdfium-random-access-candidate-search")
        .put("error", code)
      writeAtomic(resultPath, payload.toString())
    } catch (_: Throwable) {
      // A killed worker may leave only the last running heartbeat. The caller
      // treats that as interrupted and never promotes partial authority.
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
