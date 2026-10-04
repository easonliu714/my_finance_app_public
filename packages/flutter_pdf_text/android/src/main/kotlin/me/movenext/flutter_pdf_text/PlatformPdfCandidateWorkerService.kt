package me.movenext.flutter_pdf_text

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Crash-isolated exact-candidate lookup for very large sorted MOF cloud-award
 * PDFs using Android's platform PdfRenderer.
 *
 * Owner real-device evidence on the exact 115-07-08 cloud-500 source
 * (135,200,798 bytes / 87,000 pages) proved the third-party pdfiumandroid
 * newDocument path crashes natively, while platform PdfRenderer opens the
 * document and resolves an exact sorted-page candidate via bounded binary
 * search. This worker therefore owns only the >120 MiB Android API 35+ path.
 *
 * No invoice/accounting data leaves the device.
 */
class PlatformPdfCandidateWorkerService : Service() {
  companion object {
    const val EXTRA_PDF_PATH = "pdf_path"
    const val EXTRA_CANDIDATES_JSON = "candidates_json"
    const val EXTRA_EXPECTED_SOURCE_SHA256 = "expected_source_sha256"
    const val EXTRA_EXPECTED_SOURCE_BYTES = "expected_source_bytes"
    const val EXTRA_EXPECTED_CANDIDATE_UNIVERSE_SHA256 =
      "expected_candidate_universe_sha256"
    const val EXTRA_RESULT_PATH = "result_path"
    const val EXTRA_REQUEST_ID = "request_id"
    private const val NOTIFICATION_CHANNEL_ID = "cloud_award_pdf_worker"
    private const val NOTIFICATION_ID = 1320476
    private const val OPEN_HEARTBEAT_INTERVAL_MS = 2_000L
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent == null) {
      stopSelf(startId)
      return START_NOT_STICKY
    }
    startForeground(
      NOTIFICATION_ID,
      buildNotification("正在使用系統 PDF 引擎處理大型官方候選比對")
    )

    val pdfPath = intent.getStringExtra(EXTRA_PDF_PATH).orEmpty()
    val candidatesJson = intent.getStringExtra(EXTRA_CANDIDATES_JSON).orEmpty()
    val expectedSourceSha256 =
      intent.getStringExtra(EXTRA_EXPECTED_SOURCE_SHA256).orEmpty()
    val expectedSourceBytes =
      intent.getLongExtra(EXTRA_EXPECTED_SOURCE_BYTES, -1L)
    val expectedCandidateUniverseSha256 =
      intent.getStringExtra(EXTRA_EXPECTED_CANDIDATE_UNIVERSE_SHA256).orEmpty()
    val resultPath = intent.getStringExtra(EXTRA_RESULT_PATH).orEmpty()
    val requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()

    thread(start = true, name = "issue13-platform-cloud500-worker") {
      try {
        runLookup(
          pdfPath,
          candidatesJson,
          expectedSourceSha256,
          expectedSourceBytes,
          expectedCandidateUniverseSha256,
          resultPath,
          requestId
        )
      } catch (oom: OutOfMemoryError) {
        writeFailure(resultPath, requestId, "PLATFORM_WORKER_OOM")
      } catch (error: Throwable) {
        writeFailure(
          resultPath,
          requestId,
          "PLATFORM_WORKER_FAILED:${error.javaClass.simpleName}"
        )
      } finally {
        stopForeground(true)
        stopSelf(startId)
      }
    }
    return START_NOT_STICKY
  }

  private fun runLookup(
    pdfPath: String,
    candidatesJson: String,
    expectedSourceSha256: String,
    expectedSourceBytes: Long,
    expectedCandidateUniverseSha256: String,
    resultPath: String,
    requestId: String
  ) {
    require(pdfPath.isNotBlank() && resultPath.isNotBlank() && requestId.isNotBlank())
    if (Build.VERSION.SDK_INT < 35) {
      writeFailure(resultPath, requestId, "PLATFORM_RENDERER_API35_REQUIRED")
      return
    }

    val sha256Pattern = Regex("^[0-9a-fA-F]{64}$")
    if (!sha256Pattern.matches(expectedSourceSha256) ||
        !sha256Pattern.matches(expectedCandidateUniverseSha256) ||
        expectedSourceBytes <= 0L) {
      writeFailure(resultPath, requestId, "PLATFORM_WORKER_PROVENANCE_INPUT_INVALID")
      return
    }

    val source = File(pdfPath)
    if (!source.isFile) {
      writeFailure(resultPath, requestId, "PLATFORM_WORKER_SOURCE_MISSING")
      return
    }
    if (source.length() != expectedSourceBytes) {
      writeFailure(resultPath, requestId, "PLATFORM_WORKER_SOURCE_BYTES_MISMATCH")
      return
    }

    val raw = JSONArray(candidatesJson)
    val candidates = (0 until raw.length())
      .map { raw.getString(it).replace(Regex("[\\s-]"), "").uppercase() }
      .filter { Regex("^[A-Z]{2}[0-9]{8}$").matches(it) }
      .distinct()
      .sorted()
    if (candidates.isEmpty() || candidates.size != raw.length()) {
      writeFailure(resultPath, requestId, "PLATFORM_WORKER_CANDIDATE_SCOPE_INVALID")
      return
    }

    val actualCandidateUniverseSha256 = sha256Bytes(
      candidates.joinToString("\n").toByteArray(Charsets.UTF_8)
    )
    if (!actualCandidateUniverseSha256.equals(
        expectedCandidateUniverseSha256,
        ignoreCase = true
      )) {
      writeFailure(
        resultPath,
        requestId,
        "PLATFORM_WORKER_CANDIDATE_UNIVERSE_SHA256_MISMATCH"
      )
      return
    }

    writeRunning(
      resultPath, requestId, "PLATFORM_SOURCE_SHA256", 0, candidates.size,
      sourceBytesTotal = expectedSourceBytes
    )
    val actualSourceSha256 = sha256File(source) { bytesRead ->
      writeRunning(
        resultPath, requestId, "PLATFORM_SOURCE_SHA256", 0, candidates.size,
        sourceBytesRead = bytesRead,
        sourceBytesTotal = expectedSourceBytes
      )
    }
    if (!actualSourceSha256.equals(expectedSourceSha256, ignoreCase = true)) {
      writeFailure(resultPath, requestId, "PLATFORM_WORKER_SOURCE_SHA256_MISMATCH")
      return
    }

    writeRunning(
      resultPath, requestId, "PLATFORM_RENDERER_OPEN_BEGIN", 0, candidates.size,
      sourceBytesRead = expectedSourceBytes,
      sourceBytesTotal = expectedSourceBytes
    )

    var descriptor: ParcelFileDescriptor? = null
    var renderer: PdfRenderer? = null
    val opening = AtomicBoolean(true)
    val openStartedAt = SystemClock.elapsedRealtime()
    val openHeartbeat = thread(
      start = true,
      isDaemon = true,
      name = "issue13-platform-open-heartbeat"
    ) {
      while (opening.get()) {
        try {
          Thread.sleep(OPEN_HEARTBEAT_INTERVAL_MS)
          if (opening.get()) {
            writeRunning(
              resultPath, requestId, "PLATFORM_RENDERER_OPEN_WAIT", 0,
              candidates.size,
              sourceBytesRead = expectedSourceBytes,
              sourceBytesTotal = expectedSourceBytes,
              stageElapsedMs = SystemClock.elapsedRealtime() - openStartedAt
            )
          }
        } catch (_: InterruptedException) {
          break
        }
      }
    }

    try {
      descriptor =
        ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
      renderer = PdfRenderer(descriptor)
      descriptor = null
      opening.set(false)
      openHeartbeat.interrupt()

      val pageCount = renderer.pageCount
      require(pageCount > 0)
      val matched = linkedSetOf<String>()
      val matchedPages = linkedMapOf<String, Int>()
      val pagesRead = linkedSetOf<Int>()
      val pageCache = mutableMapOf<Int, List<String>>()

      writeRunning(
        resultPath, requestId, "PLATFORM_RENDERER_OPEN_OK", 0, candidates.size,
        pageCount = pageCount,
        sourceBytesRead = expectedSourceBytes,
        sourceBytesTotal = expectedSourceBytes,
        stageElapsedMs = SystemClock.elapsedRealtime() - openStartedAt
      )

      fun pageTokens(pageNumber: Int, candidateIndex: Int): List<String> {
        require(pageNumber in 1..pageCount)
        pageCache[pageNumber]?.let { return it }
        writeRunning(
          resultPath, requestId, "PLATFORM_RENDERER_PAGE_BEGIN",
          candidateIndex, candidates.size,
          pageNumber = pageNumber,
          pageCount = pageCount,
          pagesRead = pagesRead.size,
          sourceBytesRead = expectedSourceBytes,
          sourceBytesTotal = expectedSourceBytes
        )
        val page = renderer.openPage(pageNumber - 1)
        val text = page.use {
          it.textContents.joinToString("\n") { content -> content.text }
        }
        val tokens = extractInvoiceNumbers(text)
        require(tokens.isNotEmpty())
        pageCache[pageNumber] = tokens
        pagesRead.add(pageNumber)
        writeRunning(
          resultPath, requestId, "PLATFORM_RENDERER_CANDIDATE_SEARCH",
          candidateIndex, candidates.size,
          pageNumber = pageNumber,
          pageCount = pageCount,
          pagesRead = pagesRead.size,
          sourceBytesRead = expectedSourceBytes,
          sourceBytesTotal = expectedSourceBytes
        )
        return tokens
      }

      candidates.forEachIndexed { index, candidate ->
        var low = 1
        var high = pageCount
        var found = false
        while (low <= high) {
          val middle = low + ((high - low) ushr 1)
          val tokens = pageTokens(middle, index + 1)
          when {
            candidate < tokens.first() -> high = middle - 1
            candidate > tokens.last() -> low = middle + 1
            else -> {
              if (tokens.contains(candidate)) {
                matched.add(candidate)
                matchedPages[candidate] = middle
                found = true
              } else {
                listOf(middle - 1, middle + 1)
                  .filter { it in 1..pageCount }
                  .forEach { neighbor ->
                    if (!found &&
                        pageTokens(neighbor, index + 1).contains(candidate)) {
                      matched.add(candidate)
                      matchedPages[candidate] = neighbor
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
              if (!found &&
                  pageTokens(boundary, index + 1).contains(candidate)) {
                matched.add(candidate)
                matchedPages[candidate] = boundary
                found = true
              }
            }
        }
      }

      val matchedPagesJson = JSONObject()
      matchedPages.forEach { (candidate, pageNumber) ->
        matchedPagesJson.put(candidate, pageNumber)
      }
      val payload = JSONObject()
        .put("request_id", requestId)
        .put("status", "complete")
        .put("engine", "android-platform-pdfrenderer-candidate-search")
        .put("worker_pid", android.os.Process.myPid())
        .put("stage", "PLATFORM_RENDERER_COMPLETE")
        .put("page_count", pageCount)
        .put("pages_read", pagesRead.size)
        .put("candidate_count", candidates.size)
        .put("source_sha256", actualSourceSha256)
        .put("source_bytes", source.length())
        .put("candidate_universe_sha256", actualCandidateUniverseSha256)
        .put("matched", JSONArray(matched.toList()))
        .put("matched_pages", matchedPagesJson)
        .put("updated_at_ms", System.currentTimeMillis())
      writeAtomic(resultPath, payload.toString())
    } finally {
      opening.set(false)
      openHeartbeat.interrupt()
      try { renderer?.close() } catch (_: Throwable) {}
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

  private fun writeRunning(
    resultPath: String,
    requestId: String,
    stage: String,
    candidateIndex: Int,
    candidateCount: Int,
    pageNumber: Int = 0,
    pageCount: Int = 0,
    pagesRead: Int = 0,
    sourceBytesRead: Long = 0L,
    sourceBytesTotal: Long = 0L,
    stageElapsedMs: Long = 0L
  ) {
    val payload = JSONObject()
      .put("request_id", requestId)
      .put("status", "running")
      .put("engine", "android-platform-pdfrenderer-candidate-search")
      .put("worker_pid", android.os.Process.myPid())
      .put("stage", stage)
      .put("candidate_index", candidateIndex)
      .put("candidate_count", candidateCount)
      .put("page_number", pageNumber)
      .put("page_count", pageCount)
      .put("pages_read", pagesRead)
      .put("source_bytes_read", sourceBytesRead)
      .put("source_bytes_total", sourceBytesTotal)
      .put("stage_elapsed_ms", stageElapsedMs)
      .put("updated_at_ms", System.currentTimeMillis())
    writeAtomic(resultPath, payload.toString())
  }

  private fun sha256File(file: File, onProgress: (Long) -> Unit): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(64 * 1024)
    var totalRead = 0L
    var nextProgress = 8L * 1024L * 1024L
    file.inputStream().buffered().use { input ->
      while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        if (read == 0) continue
        digest.update(buffer, 0, read)
        totalRead += read
        if (totalRead >= nextProgress) {
          onProgress(totalRead)
          nextProgress = totalRead + 8L * 1024L * 1024L
        }
      }
    }
    onProgress(totalRead)
    return digest.digest().joinToString("") {
      (it.toInt() and 0xff).toString(16).padStart(2, '0')
    }
  }

  private fun sha256Bytes(bytes: ByteArray): String {
    return MessageDigest.getInstance("SHA-256")
      .digest(bytes)
      .joinToString("") {
        (it.toInt() and 0xff).toString(16).padStart(2, '0')
      }
  }

  private fun ensureNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(NotificationManager::class.java)
    val channel = NotificationChannel(
      NOTIFICATION_CHANNEL_ID,
      "雲端發票中獎資料處理",
      NotificationManager.IMPORTANCE_LOW
    ).apply {
      description = "大型財政部官方 PDF 背景候選比對"
      setShowBadge(false)
    }
    manager.createNotificationChannel(channel)
  }

  private fun buildNotification(message: String): Notification {
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(this)
    }
    return builder
      .setSmallIcon(android.R.drawable.stat_sys_download)
      .setContentTitle("雲端發票中獎資料處理中")
      .setContentText(message)
      .setCategory(Notification.CATEGORY_PROGRESS)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .build()
  }

  private fun writeFailure(resultPath: String, requestId: String, code: String) {
    if (resultPath.isBlank() || requestId.isBlank()) return
    try {
      val payload = JSONObject()
        .put("request_id", requestId)
        .put("status", "failed")
        .put("engine", "android-platform-pdfrenderer-candidate-search")
        .put("error", code)
        .put("updated_at_ms", System.currentTimeMillis())
      writeAtomic(resultPath, payload.toString())
    } catch (_: Throwable) {
      // The caller never promotes a partial candidate authority.
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
