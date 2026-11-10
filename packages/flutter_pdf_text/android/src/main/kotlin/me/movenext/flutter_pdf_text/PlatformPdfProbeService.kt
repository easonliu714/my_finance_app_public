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
  private val probeLease = LabL1NativeProbeLease()

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
      synchronized(probeLease) {
        probeLease.noteStart(startId)
        if (!probeLease.isActive()) stopSelf(startId)
      }
      return START_NOT_STICKY
    }
    // Parse extras before acquiring the lease; malformed intent data must
    // never strand the isolated native renderer worker slot.
    val pdfPath = intent.getStringExtra(EXTRA_PDF_PATH).orEmpty()
    val resultPath = intent.getStringExtra(EXTRA_RESULT_PATH).orEmpty()
    val requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
    val candidate = intent.getStringExtra(EXTRA_CANDIDATE).orEmpty()
    val admitted = synchronized(probeLease) {
      probeLease.noteStart(startId)
      probeLease.tryAcquire()
    }
    if (!admitted) {
      // Do not overwrite the incumbent's terminal result. The rejected
      // caller times out fail-closed, without a second PdfRenderer.
      return START_NOT_STICKY
    }
    try {
      thread(start = true, name = "platform-pdf-probe") {
        try {
          runProbe(pdfPath, resultPath, requestId, candidate)
        } finally {
          synchronized(probeLease) {
            // Rejected starts advance Android's startId. Stop the latest
            // start before releasing the single-flight worker lease.
            stopSelf(probeLease.latestStartId())
            probeLease.release()
          }
        }
      }
    } catch (error: Throwable) {
      synchronized(probeLease) {
        stopSelf(probeLease.latestStartId())
        probeLease.release()
      }
      throw error
    }
    return START_NOT_STICKY
  }

  private fun runProbe(
    pdfPath: String,
    resultPath: String,
    requestId: String,
    candidate: String
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
    // One fence per worker: late heartbeat must not replace a terminal JSON.
    val resultCustody = LabL1NativeResultCustody()

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
      writeResult(resultPath, status, extra, resultCustody)
    }

    appendLog(
      "PLATFORM_PROBE_PROCESS_START",
      source,
      "request=$requestId pid=$pid sdk=${Build.VERSION.SDK_INT} candidate=$candidate"
    )
    if (!source.isFile || resultPath.isBlank() || requestId.isBlank()) {
      stage.set("INPUT_INVALID")
      snapshot("failure", JSONObject().put("message", "invalid input"))
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
      // For official L1 export, reject wrong bytes/SHA and escaped paths
      // BEFORE constructing the native renderer (which can crash a process).
      val l1First = if (candidate.startsWith("LAB_L1_EXPORT:")) {
        val first = candidate.removePrefix("LAB_L1_EXPORT:").toIntOrNull()
          ?: throw IllegalStateException("L1_START_PAGE_INVALID")
        if (first < 1 || first > 100000) {
          throw IllegalStateException("L1_START_PAGE_OUT_OF_RANGE")
        }
        first
      } else null
      val l1Parent = if (l1First != null) {
        if (!Regex("^[0-9]{1,24}$").matches(requestId)) {
          throw IllegalStateException("L1_REQUEST_ID_INVALID")
        }
        val root = applicationContext.filesDir.canonicalFile
        val parent = File(resultPath).parentFile?.canonicalFile
          ?: throw IllegalStateException("L1_EXPORT_OUTSIDE_APP_FILES")
        if (!parent.path.startsWith(root.path + File.separator)) {
          throw IllegalStateException("L1_EXPORT_OUTSIDE_APP_FILES")
        }
        parent
      } else null
      val l1Sha = if (l1First != null) {
        stage.set("L1_SOURCE_PREFLIGHT_BEFORE_RENDERER")
        snapshot("running")
        val sha = LabOfficialPdfPreflight.verify(
          source, applicationContext.filesDir)
        appendLog("L1_SOURCE_PREFLIGHT_PASS", source,
          "request=$requestId sha256=$sha before_renderer=true")
        sha
      } else null
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


      // Lab L1: bounded native API35 extraction. No full-PDF or NOT_WIN
      // authority is inferred from a partial batch, even on a valid SHA.
      if (l1First != null) {
        val first = l1First
        if (first > pageCount || pageCount > 100000) {
          throw IllegalStateException("L1_START_PAGE_OUT_OF_RANGE")
        }
        val sha = l1Sha ?: throw IllegalStateException("L1_SOURCE_PREFLIGHT_MISSING")
        val parent = l1Parent ?: throw IllegalStateException("L1_EXPORT_OUTSIDE_APP_FILES")
        val target = File(parent, "l1-pages-${first}-${requestId}.jsonl")
        val pending = File(parent, target.name + ".part")
        if (target.exists() || pending.exists()) {
          throw IllegalStateException("L1_EXPORT_TARGET_COLLISION")
        }
        val last = minOf(pageCount, first + 3)
        var totalBytes = 0
        try {
          FileOutputStream(pending).use { output ->
            for (number in first..last) {
              currentPage.set(number)
              stage.set("L1_PAGE_TEXT")
              snapshot("running", JSONObject().put("page_count", pageCount))
              val text = StringBuilder()
              renderer.openPage(number - 1).use { page ->
                for (piece in page.textContents) {
                  val part = piece.text
                  if (text.length + part.length + 1 > 250000) {
                    throw IllegalStateException("L1_PAGE_TEXT_BUDGET_EXCEEDED")
                  }
                  if (text.isNotEmpty()) text.append('\n')
                  text.append(part)
                }
              }
              if (text.isEmpty()) {
                throw IllegalStateException("L1_PAGE_TEXT_EMPTY")
              }
              val record = JSONObject()
                .put("page", number)
                .put("page_count", pageCount)
                .put("pdf_sha256", sha)
                .put("engine", "android.graphics.pdf.PdfRenderer")
                .put("period", "115-07-08")
                .put("tier", "cloud-500")
                .put("text", text.toString())
              val bytes = (record.toString() + "\n").toByteArray(Charsets.UTF_8)
              if (bytes.size > 1000000 || totalBytes + bytes.size > 4000000) {
                throw IllegalStateException("L1_BATCH_BYTES_BUDGET_EXCEEDED")
              }
              output.write(bytes)
              totalBytes += bytes.size
              pagesRead.incrementAndGet()
            }
            output.flush()
            output.fd.sync()
          }
          if (!pending.renameTo(target)) {
            throw IllegalStateException("L1_EXPORT_ATOMIC_RENAME_FAILED")
          }
        } finally {
          if (pending.exists()) pending.delete()
        }
        // A finalized JSONL file is not terminal native success while the
        // PdfRenderer still owns native resources. A close failure must leave
        // the Dart dispatch fence in HOLD, never publish "complete".
        LabL1NativeTerminalCustody.publishAfterClose(
          closeResources = {
            val activeRenderer = renderer
              ?: throw IllegalStateException("L1_RENDERER_MISSING_AT_TERMINAL")
            activeRenderer.close()
            renderer = null
            descriptor?.close()
            descriptor = null
            // Lab-only evidence: renderer closure is not process exit.
            appendLog("L1_RENDERER_CLOSED_BEFORE_TERMINAL", source,
              "request=$requestId first=$first last=$last")
          },
          publishSuccess = {
            alive.set(false)
            heartbeat.interrupt()
            heartbeat.join(1000)
            stage.set("L1_PARTIAL_BATCH_COMPLETE")
            snapshot("complete", JSONObject()
              .put("page_count", pageCount)
              .put("start_page", first)
              .put("end_page", last)
              .put("pdf_sha256", sha)
              .put("export_path", target.absolutePath)
              .put("batch_only", true)
              .put("global_not_win", "HOLD"))
          }
        )
        return
      }

      if (candidate.isBlank()) {
        stage.set("PLATFORM_OPEN_COMPLETE")
        snapshot("complete", JSONObject().put("page_count", pageCount))
        return
      }

      // The search keeps its renderer alive until runProbe's finally block.
      // Capture a stable non-null handle for the nested invoiceTokens closure.
      val searchRenderer = renderer
        ?: throw IllegalStateException("PLATFORM_RENDERER_MISSING_FOR_SEARCH")
      val normalized = candidate.uppercase()
      val cache = mutableMapOf<Int, List<String>>()

      fun invoiceTokens(pageNumber: Int): List<String> {
        cache[pageNumber]?.let { return it }
        currentPage.set(pageNumber)
        stage.set("PLATFORM_PAGE_TEXT_BEGIN")
        snapshot("running", JSONObject().put("page_count", pageCount))
        val pageStartedAt = SystemClock.elapsedRealtime()
        val page = searchRenderer.openPage(pageNumber - 1)
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
    }
  }

  private fun writeResult(
    path: String,
    status: String,
    payload: JSONObject,
    custody: LabL1NativeResultCustody
  ) {
    if (path.isBlank()) return
    try {
      // Preserve the previous complete JSON when a heartbeat/terminal
      // replacement fails; never delete it or fall back to in-place writes.
      custody.publish(path, status, payload.toString())
    } catch (_: Throwable) {
      // Dart's bounded polling remains fail-closed on an unwritable result.
    }
  }

  private fun readNativeMemoryEvidence(): String {
    val pssKb = try {
      val info = android.os.Debug.MemoryInfo()
      android.os.Debug.getMemoryInfo(info)
      info.totalPss
    } catch (_: Throwable) {
      null
    }
    val rssKb = try {
      val line = File("/proc/self/status").useLines { lines ->
        lines.firstOrNull { it.startsWith("VmRSS:") }
      }
      LabL1NativeMemoryEvidence.rssKbFromProcStatus(line.orEmpty())
    } catch (_: Throwable) {
      null
    }
    return LabL1NativeMemoryEvidence.format(pssKb, rssKb)
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
        // Sample this isolated worker's PSS/RSS; never infer process exit.
        append(" ").append(readNativeMemoryEvidence())
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
