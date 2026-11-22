package me.movenext.flutter_pdf_text

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.legere.pdfiumandroid.PdfiumCore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
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
    const val EXTRA_EXPECTED_SOURCE_SHA256 = "expected_source_sha256"
    const val EXTRA_EXPECTED_SOURCE_BYTES = "expected_source_bytes"
    const val EXTRA_EXPECTED_CANDIDATE_UNIVERSE_SHA256 =
      "expected_candidate_universe_sha256"
    const val EXTRA_RESULT_PATH = "result_path"
    const val EXTRA_REQUEST_ID = "request_id"
    private const val NOTIFICATION_CHANNEL_ID = "cloud_award_pdf_worker"
    private const val NOTIFICATION_ID = 1320475
    private const val OPEN_HEARTBEAT_INTERVAL_MS = 5_000L
  }

  private lateinit var pdfiumCore: PdfiumCore
  // One heavy native document per dedicated worker process, never per Intent.
  private val singleFlight = PdfiumWorkerSingleFlightAdmission()
  // onStartCommand and worker completion both update this on the main looper.
  private var latestStartId = 0

  override fun onCreate() {
    super.onCreate()
    pdfiumCore = PdfiumCore(applicationContext)
    ensureNotificationChannel()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    latestStartId = startId
    if (intent == null) {
      // A null redelivery cannot kill a legitimate active native PDF read.
      if (!singleFlight.isActive()) stopSelfResult(latestStartId)
      return START_NOT_STICKY
    }

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
    if (!singleFlight.tryStart(requestId, resultPath)) {
      // The plugin generates a distinct UUID result file for each request.
      // Never overwrite the live worker's file if a malformed caller reuses it.
      if (!singleFlight.isActivePath(resultPath)) {
        writeFailure(resultPath, requestId, "PDFIUM_WORKER_CONCURRENT_REQUEST_HOLD")
      }
      return START_NOT_STICKY
    }
    try {
      startForeground(
        NOTIFICATION_ID,
        buildNotification("正在處理大型官方 PDF 候選比對")
      )
      thread(start = true, name = "issue13-cloud500-worker") {
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
          writeFailure(resultPath, requestId, "PDFIUM_WORKER_OOM")
        } catch (error: Throwable) {
          writeFailure(
            resultPath,
            requestId,
            "PDFIUM_WORKER_FAILED:${error.javaClass.simpleName}"
          )
        } finally {
          // Serialize release and stop with onStartCommand on the main looper.
          // A rejected newer startId must not strand the foreground service;
          // an older worker must never stop a newly admitted request.
          Handler(Looper.getMainLooper()).post {
            if (singleFlight.finish(requestId)) {
              stopForeground(true)
              stopSelfResult(latestStartId)
            }
          }
        }
      }
    } catch (error: Throwable) {
      if (singleFlight.finish(requestId)) {
        writeFailure(resultPath, requestId, "PDFIUM_WORKER_START_FAILED")
        stopForeground(true)
        stopSelfResult(latestStartId)
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
    val sha256Pattern = Regex("^[0-9a-fA-F]{64}$")
    if (!sha256Pattern.matches(expectedSourceSha256) ||
        !sha256Pattern.matches(expectedCandidateUniverseSha256) ||
        expectedSourceBytes <= 0L) {
      writeFailure(resultPath, requestId, "PDFIUM_WORKER_PROVENANCE_INPUT_INVALID")
      return
    }

    val source = File(pdfPath)
    if (!source.isFile) {
      writeFailure(resultPath, requestId, "PDFIUM_WORKER_SOURCE_MISSING")
      return
    }
    if (source.length() != expectedSourceBytes) {
      writeFailure(resultPath, requestId, "PDFIUM_WORKER_SOURCE_BYTES_MISMATCH")
      return
    }

    val raw = JSONArray(candidatesJson)
    val candidates = (0 until raw.length())
      .map { raw.getString(it).replace(Regex("[\\s-]"), "").uppercase() }
      .filter { Regex("^[A-Z]{2}[0-9]{8}$").matches(it) }
      .distinct()
      .sorted()
    // A vacuous candidate universe cannot establish cloud-500 authority. Fail
    // before hashing the source or opening PDFium so no empty lookup can ever
    // be promoted as a completed verification.
    if (candidates.isEmpty() || candidates.size != raw.length()) {
      writeFailure(resultPath, requestId, "PDFIUM_WORKER_CANDIDATE_SCOPE_INVALID")
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
        "PDFIUM_WORKER_CANDIDATE_UNIVERSE_SHA256_MISMATCH"
      )
      return
    }

    writeRunning(
      resultPath = resultPath,
      requestId = requestId,
      stage = "PDFIUM_SOURCE_SHA256",
      candidateIndex = 0,
      candidateCount = candidates.size,
      sourceBytesTotal = expectedSourceBytes
    )
    // Copy and SHA-verify one immutable app-private inode before PDFium opens it.
    // The original pathname is never reopened after validation (TOCTOU closed).
    val verified = try {
      PdfiumWorkerVerifiedSnapshot.open(
        source, cacheDir, expectedSourceBytes, expectedSourceSha256
      ) { bytesRead ->
        writeRunning(
          resultPath = resultPath,
          requestId = requestId,
          stage = "PDFIUM_SOURCE_SHA256",
          candidateIndex = 0,
          candidateCount = candidates.size,
          sourceBytesRead = bytesRead,
          sourceBytesTotal = expectedSourceBytes
        )
      }
    } catch (error: IllegalStateException) {
      writeFailure(resultPath, requestId, error.message ?: "PDFIUM_WORKER_SNAPSHOT_FAILED")
      return
    }
    val actualSourceSha256 = verified.sha256
    verified.use { snapshot ->
    writeRunning(
      resultPath = resultPath,
      requestId = requestId,
      stage = "PDFIUM_OPEN_BEGIN",
      candidateIndex = 0,
      candidateCount = candidates.size,
      sourceBytesRead = expectedSourceBytes,
      sourceBytesTotal = expectedSourceBytes
    )

    var descriptor: ParcelFileDescriptor? = null
    val opening = AtomicBoolean(true)
    val openStartedAt = SystemClock.elapsedRealtime()
    val openHeartbeat = thread(
      start = true,
      isDaemon = true,
      name = "issue13-cloud500-open-heartbeat"
    ) {
      while (opening.get()) {
        try {
          Thread.sleep(OPEN_HEARTBEAT_INTERVAL_MS)
          if (opening.get()) {
            writeRunning(
              resultPath = resultPath,
              requestId = requestId,
              stage = "PDFIUM_OPEN_WAIT",
              candidateIndex = 0,
              candidateCount = candidates.size,
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
      descriptor = ParcelFileDescriptor.dup(snapshot.file.fd)
      val document = pdfiumCore.newDocument(descriptor)
      opening.set(false)
      openHeartbeat.interrupt()
      descriptor = null // ownership transferred to PdfDocument
      document.use {
        val pageCount = document.getPageCount()
        require(pageCount > 0)
        // The coverage search owns match accumulation. The worker only
        // retains the bounded set of visited page numbers for diagnostics.
        val pagesRead = linkedSetOf<Int>()

        writeRunning(
          resultPath = resultPath,
          requestId = requestId,
          stage = "PDFIUM_OPEN_OK",
          candidateIndex = 0,
          candidateCount = candidates.size,
          pageCount = pageCount
        )

        fun pageTokens(
          pageNumber: Int,
          candidateIndex: Int,
          fullCoverage: Boolean = false
        ): List<String> {
          require(pageNumber in 1..pageCount)
          // A global fallback may visit 77k pages. Persist bounded progress
          // rather than writing 154k JSON heartbeats to flash storage.
          val report = !fullCoverage || pageNumber == 1 ||
            pageNumber == pageCount || pageNumber % 128 == 0
          if (report) writeRunning(
            resultPath = resultPath,
            requestId = requestId,
            stage = if (fullCoverage) "PDFIUM_FULL_COVERAGE" else "PDFIUM_PAGE_BEGIN",
            candidateIndex = candidateIndex,
            candidateCount = candidates.size,
            pageNumber = pageNumber,
            pageCount = pageCount,
            pagesRead = pagesRead.size
          )
          val page = document.openPage(pageNumber - 1)
            ?: throw IllegalStateException("PDFIUM_PAGE_OPEN_NULL")
          val text = page.use {
            val textPage = page.openTextPage()
              ?: throw IllegalStateException("PDFIUM_TEXT_PAGE_OPEN_NULL")
            textPage.use {
              val count = textPage.textPageCountChars()
              if (count <= 0) "" else textPage.textPageGetText(0, count).orEmpty()
            }
          }
          pagesRead.add(pageNumber)
          if (report) writeRunning(
            resultPath = resultPath,
            requestId = requestId,
            stage = if (fullCoverage) "PDFIUM_FULL_COVERAGE" else "PDFIUM_CANDIDATE_SEARCH",
            candidateIndex = candidateIndex,
            candidateCount = candidates.size,
            pageNumber = pageNumber,
            pageCount = pageCount,
            pagesRead = pagesRead.size
          )
          return extractInvoiceNumbers(text)
        }

        // Native binary search is a positive-only acceleration. Without an
        // independently established global page ordering it can skip a real
        // match. One bounded-memory full-document fallback checks all pages
        // for any unresolved candidate; incomplete/negative evidence stays HOLD.
        val search = PdfiumCandidateCoverageSearch.search(
          candidates, pageCount
        ) { page, index, fullCoverage ->
          pageTokens(page, index, fullCoverage)
        }
        if (search.unresolved.isNotEmpty()) {
          // One SHA-pinned PDF is still not an independently attested negative.
          // No "complete" JSON or absent-result list may leave this worker.
          writeFailure(resultPath, requestId, "PDFIUM_WORKER_NEGATIVE_UNATTESTED_HOLD")
          return
        }
        val matchedPages = search.matchedPages
        val matched = candidates.filter { matchedPages.containsKey(it) }

        val matchedPagesJson = JSONObject()
        matchedPages.forEach { (candidate, pageNumber) ->
          matchedPagesJson.put(candidate, pageNumber)
        }
        val payload = JSONObject()
          .put("request_id", requestId)
          .put("status", "complete")
          .put("engine", "pdfium-random-access-candidate-search")
          .put("worker_pid", android.os.Process.myPid())
          .put("stage", "PDFIUM_COMPLETE")
          .put("page_count", pageCount)
          .put("pages_read", pagesRead.size)
          .put("full_coverage_scan", search.fullCoverageScan)
          .put("negative_authority", "HOLD")
          .put("candidate_count", candidates.size)
          .put("source_sha256", actualSourceSha256)
          .put("source_bytes", snapshot.bytes)
          .put("candidate_universe_sha256", actualCandidateUniverseSha256)
          .put("matched", JSONArray(matched.toList()))
          .put("matched_pages", matchedPagesJson)
        writeAtomic(resultPath, payload.toString())
      }
    } finally {
      opening.set(false)
      openHeartbeat.interrupt()
      try { descriptor?.close() } catch (_: Exception) {}
    }
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
      .put("engine", "pdfium-random-access-candidate-search")
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
        .put("engine", "pdfium-random-access-candidate-search")
        .put("error", code)
      writeAtomic(resultPath, payload.toString())
    } catch (_: Throwable) {
      // A killed worker may leave only the last running heartbeat. The caller
      // treats that as interrupted and never promotes partial authority.
    }
  }

  private fun writeAtomic(path: String, content: String) {
    // Never fall back to truncating the published result on rename failure.
    // The caller treats the prior heartbeat as interrupted, not completed.
    PdfiumWorkerAtomicResult.write(File(path), content)
  }
}
