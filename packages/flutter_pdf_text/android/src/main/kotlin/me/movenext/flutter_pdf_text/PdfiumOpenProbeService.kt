package me.movenext.flutter_pdf_text

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import io.legere.pdfiumandroid.PdfiumCore
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class PdfiumOpenProbeService : Service() {
  companion object {
    const val EXTRA_PDF_PATH = "pdf_path"
    const val EXTRA_RESULT_PATH = "result_path"
    const val EXTRA_REQUEST_ID = "request_id"
    private const val HEARTBEAT_MS = 2_000L
    private const val LOG_FILE = "issue13_cloud500_diag_native.log"
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
    val resultPath = intent.getStringExtra(EXTRA_RESULT_PATH).orEmpty()
    val requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
    thread(start = true, name = "cloud500-open-probe") {
      runProbe(pdfPath, resultPath, requestId, startId)
    }
    return START_NOT_STICKY
  }

  private fun runProbe(
    pdfPath: String,
    resultPath: String,
    requestId: String,
    startId: Int
  ) {
    val source = File(pdfPath)
    val pid = Process.myPid()
    val startedAt = SystemClock.elapsedRealtime()
    appendLog(
      "OPEN_PROBE_PROCESS_START",
      source,
      "request=$requestId pid=$pid pdfium=2.0.3"
    )
    if (!source.isFile || resultPath.isBlank() || requestId.isBlank()) {
      writeResult(
        resultPath,
        JSONObject()
          .put("request_id", requestId)
          .put("status", "failure")
          .put("stage", "INPUT_INVALID")
          .put("pid", pid)
          .put("updated_at_ms", System.currentTimeMillis())
      )
      stopSelf(startId)
      return
    }

    val alive = AtomicBoolean(true)
    writeResult(
      resultPath,
      JSONObject()
        .put("request_id", requestId)
        .put("status", "running")
        .put("stage", "PDFIUM_NEW_DOCUMENT_BEGIN")
        .put("pid", pid)
        .put("elapsed_ms", 0L)
        .put("updated_at_ms", System.currentTimeMillis())
    )
    appendLog("PDFIUM_NEW_DOCUMENT_BEGIN", source, "request=$requestId pid=$pid")

    val heartbeat = thread(
      start = true,
      isDaemon = true,
      name = "cloud500-open-probe-heartbeat"
    ) {
      while (alive.get()) {
        try {
          Thread.sleep(HEARTBEAT_MS)
          if (!alive.get()) break
          val elapsed = SystemClock.elapsedRealtime() - startedAt
          writeResult(
            resultPath,
            JSONObject()
              .put("request_id", requestId)
              .put("status", "running")
              .put("stage", "PDFIUM_NEW_DOCUMENT_WAIT")
              .put("pid", pid)
              .put("elapsed_ms", elapsed)
              .put("updated_at_ms", System.currentTimeMillis())
          )
          appendLog(
            "PDFIUM_NEW_DOCUMENT_WAIT",
            source,
            "request=$requestId pid=$pid elapsed_ms=$elapsed"
          )
        } catch (_: InterruptedException) {
          break
        }
      }
    }

    var descriptor: ParcelFileDescriptor? = null
    try {
      descriptor =
        ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
      val document = pdfiumCore.newDocument(descriptor)
      descriptor = null
      val pageCount = document.getPageCount()
      val elapsed = SystemClock.elapsedRealtime() - startedAt
      appendLog(
        "PDFIUM_NEW_DOCUMENT_OK",
        source,
        "request=$requestId pid=$pid page_count=$pageCount elapsed_ms=$elapsed"
      )
      writeResult(
        resultPath,
        JSONObject()
          .put("request_id", requestId)
          .put("status", "complete")
          .put("stage", "PDFIUM_OPEN_OK")
          .put("pid", pid)
          .put("page_count", pageCount)
          .put("elapsed_ms", elapsed)
          .put("updated_at_ms", System.currentTimeMillis())
      )
      document.close()
    } catch (error: Throwable) {
      val elapsed = SystemClock.elapsedRealtime() - startedAt
      appendLog(
        "PDFIUM_OPEN_CAUGHT_FAILURE",
        source,
        "request=$requestId pid=$pid elapsed_ms=$elapsed " +
          "error=${error.javaClass.name} message=${error.message}"
      )
      writeResult(
        resultPath,
        JSONObject()
          .put("request_id", requestId)
          .put("status", "failure")
          .put("stage", "PDFIUM_OPEN_CAUGHT_FAILURE")
          .put("pid", pid)
          .put("elapsed_ms", elapsed)
          .put("error", error.javaClass.name)
          .put("message", error.message ?: "")
          .put("updated_at_ms", System.currentTimeMillis())
      )
    } finally {
      alive.set(false)
      heartbeat.interrupt()
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
