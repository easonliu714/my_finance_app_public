package me.movenext.flutter_pdf_text

import android.app.Service
import android.content.Intent
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

class PlatformPdfProbeService : Service() {
  companion object {
    const val EXTRA_PDF_PATH = "pdf_path"
    const val EXTRA_RESULT_PATH = "result_path"
    const val EXTRA_REQUEST_ID = "request_id"
    const val EXTRA_CANDIDATE = "candidate"
    private const val HEARTBEAT_MS = 2_000L
    private const val LOG_FILE = "issue13_cloud500_diag_native.log"
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent == null) {
      stopSelf(startId)
      return START_NOT_STICKY
    }
    val pdfPath = intent.getStringExtra(EXTRA_PDF_PATH).orEmpty()
    val resultPath = intent.getStringExtra(EXTRA_RESULT_PATH).orEmpty()
    val requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
    val candidate = intent.getStringExtra(EXTRA_CANDIDATE).orEmpty()
    thread(start = true, name = "platform-pdf-probe") {
      runProbe(pdfPath, resultPath, requestId, candidate, startId)
    }
    return START_NOT_STICKY
  }

  private fun runProbe(
    pdfPath: String,
    resultPath: String,
    requestId: String,
    candidate: String,
    startId: Int
  ) {
    val source = File(pdfPath)
    val pid = Process.myPid()
    val startedAt = SystemClock.elapsedRealtime()
    val alive = AtomicBoolean(true)
    val stage = AtomicReference("PLATFORM_OPEN_BEGIN")
    val currentPage = AtomicInteger(0)
    val pagesRead = AtomicInteger(0)
    var descriptor: ParcelFileDescriptor? = null
    var renderer: PdfRenderer? = null

    fun snapshot(status: String, extra: JSONObject = JSONObject()) {
      extra
        .put("request_id", requestId)
        .put("status", status)
        .put("stage", stage.get())
        .put("pid", pid)
        .put("elapsed_ms", SystemClock.elapsedRealtime() - startedAt)
        .put("current_page", currentPage.get())
        .put("pages_read", pagesRead.get())
        .put("updated_at_ms", System.currentTimeMillis())
      writeResult(resultPath, extra)
    }

    appendLog(
      "PLATFORM_PROBE_PROCESS_START",
      source,
      "request=$requestId pid=$pid sdk=${Build.VERSION.SDK_INT} candidate=$candidate"
    )
    if (!source.isFile || resultPath.isBlank() || requestId.isBlank()) {
      stage.set("INPUT_INVALID")
      snapshot("failure", JSONObject().put("message", "invalid input"))
      stopSelf(startId)
      return
    }
    if (Build.VERSION.SDK_INT < 35) {
      stage.set("UNSUPPORTED_SDK")
      snapshot(
        "failure",
        JSONObject()
          .put("message", "PdfRenderer text APIs require API 35+")
          .put("sdk", Build.VERSION.SDK_INT)
      )
      stopSelf(startId)
      return
    }

    snapshot("running")
    val heartbeat = thread(
      start = true,
      isDaemon = true,
      name = "platform-pdf-probe-heartbeat"
    ) {
      while (alive.get()) {
        try {
          Thread.sleep(HEARTBEAT_MS)
          if (!alive.get()) break
          snapshot("running")
          appendLog(
            "PLATFORM_PROBE_HEARTBEAT",
            source,
            "request=$requestId stage=${stage.get()} page=${currentPage.get()} " +
              "pages_read=${pagesRead.get()} elapsed_ms=" +
              (SystemClock.elapsedRealtime() - startedAt)
          )
        } catch (_: InterruptedException) {
          break
        }
      }
    }

    try {
      descriptor =
        ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
      stage.set("PLATFORM_RENDERER_CONSTRUCT_BEGIN")
      snapshot("running")
      appendLog("PLATFORM_RENDERER_CONSTRUCT_BEGIN", source, "request=$requestId")

      renderer = PdfRenderer(descriptor)
      descriptor = null
      val pageCount = renderer.pageCount

      stage.set("PLATFORM_RENDERER_OPEN_OK")
      snapshot("running", JSONObject().put("page_count", pageCount))
      appendLog(
        "PLATFORM_RENDERER_OPEN_OK",
        source,
        "request=$requestId page_count=$pageCount elapsed_ms=" +
          (SystemClock.elapsedRealtime() - startedAt)
      )

      if (candidate.isBlank()) {
        stage.set("PLATFORM_OPEN_COMPLETE")
        snapshot("complete", JSONObject().put("page_count", pageCount))
        return
      }

      val normalized = candidate.uppercase()
      val cache = mutableMapOf<Int, List<String>>()

      fun invoiceTokens(pageNumber: Int): List<String> {
        cache[pageNumber]?.let { return it }
        currentPage.set(pageNumber)
        stage.set("PLATFORM_PAGE_TEXT_BEGIN")
        snapshot("running", JSONObject().put("page_count", pageCount))
        val pageStartedAt = SystemClock.elapsedRealtime()
        val page = renderer.openPage(pageNumber - 1)
        val text = page.use {
          it.textContents.joinToString("\n") { content -> content.text }
        }
        val pattern = Regex("[A-Z]\\s*[A-Z](?:\\s*[0-9]){8}")
        val tokens = pattern.findAll(text.uppercase())
          .map { it.value.replace(Regex("\\s+"), "") }
          .filter { Regex("^[A-Z]{2}[0-9]{8}$").matches(it) }
          .distinct()
          .sorted()
          .toList()
        pagesRead.incrementAndGet()
        cache[pageNumber] = tokens
        appendLog(
          "PLATFORM_PAGE_TEXT_OK",
          source,
          "request=$requestId page=$pageNumber chars=${text.length} " +
            "tokens=${tokens.size} first=${tokens.firstOrNull() ?: "-"} " +
            "last=${tokens.lastOrNull() ?: "-"} elapsed_ms=" +
            (SystemClock.elapsedRealtime() - pageStartedAt)
        )
        stage.set("PLATFORM_BINARY_SEARCH")
        snapshot("running", JSONObject().put("page_count", pageCount))
        if (tokens.isEmpty()) {
          throw IllegalStateException("PLATFORM_PAGE_HAS_NO_INVOICE_TOKENS page=$pageNumber")
        }
        return tokens
      }

      var low = 1
      var high = pageCount
      var matchedPage = 0
      stage.set("PLATFORM_BINARY_SEARCH")
      while (low <= high) {
        val middle = low + ((high - low) shr 1)
        val tokens = invoiceTokens(middle)
        val first = tokens.first()
        val last = tokens.last()
        appendLog(
          "PLATFORM_BINARY_STEP",
          source,
          "request=$requestId candidate=$normalized low=$low high=$high " +
            "middle=$middle first=$first last=$last"
        )
        when {
          normalized < first -> high = middle - 1
          normalized > last -> low = middle + 1
          tokens.contains(normalized) -> {
            matchedPage = middle
            break
          }
          else -> {
            for (neighbor in intArrayOf(middle - 1, middle + 1)) {
              if (neighbor < 1 || neighbor > pageCount) continue
              if (invoiceTokens(neighbor).contains(normalized)) {
                matchedPage = neighbor
                break
              }
            }
            break
          }
        }
      }

      stage.set("PLATFORM_SEARCH_COMPLETE")
      snapshot(
        "complete",
        JSONObject()
          .put("page_count", pageCount)
          .put("candidate", normalized)
          .put("matched", matchedPage > 0)
          .put("matched_page", matchedPage)
      )
      appendLog(
        "PLATFORM_SEARCH_COMPLETE",
        source,
        "request=$requestId candidate=$normalized matched=${matchedPage > 0} " +
          "matched_page=$matchedPage pages_read=${pagesRead.get()} page_count=$pageCount " +
          "elapsed_ms=" + (SystemClock.elapsedRealtime() - startedAt)
      )
    } catch (error: Throwable) {
      stage.set("PLATFORM_CAUGHT_FAILURE")
      snapshot(
        "failure",
        JSONObject()
          .put("error", error.javaClass.name)
          .put("message", error.message ?: "")
      )
      appendLog(
        "PLATFORM_CAUGHT_FAILURE",
        source,
        "request=$requestId error=${error.javaClass.name} message=${error.message} " +
          "stack=${android.util.Log.getStackTraceString(error).replace("\n", "\\n")}"
      )
    } finally {
      alive.set(false)
      heartbeat.interrupt()
      try { renderer?.close() } catch (_: Throwable) {}
      try { descriptor?.close() } catch (_: Throwable) {}
      stopSelf(startId)
    }
  }

  private fun writeResult(path: String, payload: JSONObject) {
    if (path.isBlank()) return
    try {
      val target = File(path)
      target.parentFile?.mkdirs()
      val temp = File(target.parentFile, target.name + ".tmp")
      temp.writeText(payload.toString())
      if (target.exists()) target.delete()
      if (!temp.renameTo(target)) {
        target.writeText(payload.toString())
        temp.delete()
      }
    } catch (_: Throwable) {
    }
  }

  private fun appendLog(event: String, file: File, detail: String = "") {
    try {
      val runtime = Runtime.getRuntime()
      val used = runtime.totalMemory() - runtime.freeMemory()
      val line = buildString {
        append(System.currentTimeMillis())
        append(" event=").append(event)
        append(" pid=").append(Process.myPid())
        append(" thread=").append(Thread.currentThread().name)
        append(" file_bytes=").append(if (file.isFile) file.length() else 0L)
        append(" heap_used=").append(used)
        append(" heap_total=").append(runtime.totalMemory())
        append(" heap_max=").append(runtime.maxMemory())
        if (detail.isNotBlank()) append(" detail=").append(detail)
        append("\n")
      }
      val logFile = File(applicationContext.filesDir, LOG_FILE)
      FileOutputStream(logFile, true).use { output ->
        output.write(line.toByteArray(Charsets.UTF_8))
        output.flush()
        output.fd.sync()
      }
    } catch (_: Throwable) {
    }
  }
}
