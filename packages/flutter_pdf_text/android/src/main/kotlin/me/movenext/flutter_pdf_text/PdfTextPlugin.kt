package me.movenext.flutter_pdf_text

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.annotation.NonNull
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.legere.pdfiumandroid.PdfDocument as PdfiumDocument
import io.legere.pdfiumandroid.PdfiumCore
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/** PdfTextPlugin */
class PdfTextPlugin: FlutterPlugin, MethodCallHandler {

  private lateinit var applicationContext: Context
  private val openDocuments = ConcurrentHashMap<String, PDDocument>()
  private val openDocumentPaths = ConcurrentHashMap<String, String>()
  private val pdfiumDocuments = ConcurrentHashMap<String, PdfiumDocument>()
  private val pdfiumDocumentPaths = ConcurrentHashMap<String, String>()
  private val diagnosticFileName = "flutter_pdf_text_last_diagnostic.txt"
  private lateinit var pdfiumCore: PdfiumCore

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = flutterPluginBinding.applicationContext
    val channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pdf_text")
    channel.setMethodCallHandler(this)
    PDFBoxResourceLoader.init(applicationContext)
    pdfiumCore = PdfiumCore(applicationContext)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    thread (start = true) {
      when (call.method) {
          "initDoc" -> {
            val args = call.arguments as Map<*, *>
            val path = args["path"] as String
            val password = args["password"] as String
            initDoc(result, path, password)
          }
          "openDocSession" -> {
            val args = call.arguments as Map<*, *>
            val path = args["path"] as String
            val password = args["password"] as String
            openDocSession(result, path, password)
          }
          "getDocSessionPageText" -> {
            val args = call.arguments as Map<*, *>
            val sessionId = args["sessionId"] as String
            val pageNumber = args["number"] as Int
            getDocSessionPageText(result, sessionId, pageNumber)
          }
          "closeDocSession" -> {
            val args = call.arguments as Map<*, *>
            val sessionId = args["sessionId"] as String
            closeDocSession(result, sessionId)
          }
          "getLastDiagnostic" -> {
            getLastDiagnostic(result)
          }
          "clearLastDiagnostic" -> {
            clearLastDiagnostic(result)
          }
          "openPdfiumSession" -> {
            val args = call.arguments as Map<*, *>
            val path = args["path"] as String
            openPdfiumSession(result, path)
          }
          "getPdfiumSessionPageText" -> {
            val args = call.arguments as Map<*, *>
            val sessionId = args["sessionId"] as String
            val pageNumber = args["number"] as Int
            getPdfiumSessionPageText(result, sessionId, pageNumber)
          }
          "closePdfiumSession" -> {
            val args = call.arguments as Map<*, *>
            val sessionId = args["sessionId"] as String
            closePdfiumSession(result, sessionId)
          }
          "markExtractionComplete" -> {
            val args = call.arguments as Map<*, *>
            val path = args["path"] as String
            writeDiagnostic("EXTRACTION_COMPLETE", path)
            Handler(Looper.getMainLooper()).post { result.success(true) }
          }
          "getDocPageText" -> {
            val args = call.arguments as Map<*, *>
            val path = args["path"] as String
            val pageNumber = args["number"] as Int
            val password = args["password"] as String
            getDocPageText(result, path, pageNumber, password)
          }
          "getDocText" -> {
            val args = call.arguments as Map<*, *>
            val path = args["path"] as String
            @Suppress("UNCHECKED_CAST")
            val missingPagesNumbers = args["missingPagesNumbers"] as List<Int>
            val password = args["password"] as String
            getDocText(result, path, missingPagesNumbers, password)
          }
          else -> {
            Handler(Looper.getMainLooper()).post {
              result.notImplemented()
            }
          }
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    openDocuments.values.forEach { doc ->
      try { doc.close() } catch (_: Exception) {}
    }
    openDocuments.clear()
    openDocumentPaths.clear()
    pdfiumDocuments.values.forEach { document ->
      try { document.close() } catch (_: Exception) {}
    }
    pdfiumDocuments.clear()
    pdfiumDocumentPaths.clear()
  }

  /**
    Initializes the PDF document and returns some information into the channel.
   */
  private fun initDoc(result: Result, path: String, password: String) {
    getDoc(result, path, password)?.use { doc ->
      // Getting the length of the PDF document in pages.
      val length = doc.numberOfPages

      val info = doc.documentInformation

      var creationDate: String? = null
      if (info.creationDate != null) {
        creationDate = info.creationDate.time.toString()
      }
      var modificationDate: String? = null
      if (info.modificationDate != null) {
        modificationDate = info.modificationDate.time.toString()
      }
      val data = hashMapOf<String, Any>(
              "length" to length,
              "info" to hashMapOf("author" to info.author,
                      "creationDate" to creationDate,
                      "modificationDate" to modificationDate,
                      "creator" to info.creator, "producer" to info.producer,
                      "keywords" to splitKeywords(info.keywords),
                      "title" to info.title, "subject" to info.subject
              )
      )
      doc.close()
      Handler(Looper.getMainLooper()).post {
        result.success(data)
      }
    }
  }

  /** Opens one temp-file-backed PDFBox document for bounded page iteration. */
  private fun openDocSession(result: Result, path: String, password: String) {
    val doc = getDoc(result, path, password) ?: return
    val sessionId = UUID.randomUUID().toString()
    openDocuments[sessionId] = doc
    openDocumentPaths[sessionId] = path
    writeDiagnostic("SESSION_OPEN", path, pageCount = doc.numberOfPages)
    Handler(Looper.getMainLooper()).post {
      result.success(hashMapOf("sessionId" to sessionId, "length" to doc.numberOfPages))
    }
  }

  /** Reads exactly one page from an already-open document without reloading it. */
  private fun getDocSessionPageText(result: Result, sessionId: String, pageNumber: Int) {
    val doc = openDocuments[sessionId]
    if (doc == null) {
      Handler(Looper.getMainLooper()).post {
        result.error("PDF_SESSION_NOT_FOUND", "PDF session is not available", null)
      }
      return
    }
    if (pageNumber < 1 || pageNumber > doc.numberOfPages) {
      Handler(Looper.getMainLooper()).post {
        result.error("PDF_PAGE_OUT_OF_RANGE", "PDF page is outside document bounds", null)
      }
      return
    }
    val path = openDocumentPaths[sessionId] ?: ""
    writeDiagnostic("PAGE_BEGIN", path, pageNumber, doc.numberOfPages)
    try {
      val stripper = PDFTextStripper()
      stripper.startPage = pageNumber
      stripper.endPage = pageNumber
      val text = stripper.getText(doc)
      writeDiagnostic("PAGE_OK", path, pageNumber, doc.numberOfPages)
      Handler(Looper.getMainLooper()).post { result.success(text) }
    } catch (oom: OutOfMemoryError) {
      writeDiagnostic("PAGE_OOM", path, pageNumber, doc.numberOfPages, oom.javaClass.simpleName)
      val doomed = openDocuments.remove(sessionId)
      openDocumentPaths.remove(sessionId)
      try { doomed?.close() } catch (_: Exception) {}
      Handler(Looper.getMainLooper()).post {
        result.error("PDF_PAGE_OOM", "PDF page extraction exhausted memory", null)
      }
    } catch (e: Exception) {
      writeDiagnostic("PAGE_FAILED", path, pageNumber, doc.numberOfPages, e.javaClass.simpleName)
      Handler(Looper.getMainLooper()).post {
        result.error("PDF_SESSION_PAGE_FAILED", e.message, null)
      }
    }
  }

  /** Closes the bounded native document session even when Dart parsing fails. */
  private fun closeDocSession(result: Result, sessionId: String) {
    val doc = openDocuments.remove(sessionId)
    val path = openDocumentPaths.remove(sessionId) ?: ""
    val pageCount = doc?.numberOfPages ?: 0
    try { doc?.close() } catch (_: Exception) {}
    writeDiagnostic("SESSION_CLOSED", path, pageCount = pageCount)
    Handler(Looper.getMainLooper()).post { result.success(true) }
  }

  private fun clearLastDiagnostic(result: Result) {
    try {
      File(applicationContext.filesDir, diagnosticFileName).delete()
    } catch (_: Throwable) {
      // Best effort only.
    }
    Handler(Looper.getMainLooper()).post { result.success(true) }
  }

  /**
   * Opens a PDF through native PDFium instead of materializing PDFBox state on
   * the Java heap. This path is reserved for very large sorted MOF cloud-award
   * PDFs where PDFBox can exhaust the ~256 MB Android heap at document open.
   */
  private fun openPdfiumSession(result: Result, path: String) {
    writeDiagnostic("PDFIUM_OPEN_BEGIN", path)
    val file = File(path)
    var descriptor: ParcelFileDescriptor? = null
    try {
      descriptor = ParcelFileDescriptor.open(
        file,
        ParcelFileDescriptor.MODE_READ_ONLY
      )
      val document = pdfiumCore.newDocument(descriptor)
      descriptor = null // ownership transferred to PdfDocument
      val pageCount = document.getPageCount()
      if (pageCount <= 0) {
        document.close()
        writeDiagnostic("PDFIUM_OPEN_FAILED", path, error = "EMPTY_DOCUMENT")
        Handler(Looper.getMainLooper()).post {
          result.error("PDFIUM_DOCUMENT_EMPTY", "PDFium document has no pages", null)
        }
        return
      }
      val sessionId = UUID.randomUUID().toString()
      pdfiumDocuments[sessionId] = document
      pdfiumDocumentPaths[sessionId] = path
      writeDiagnostic("PDFIUM_OPEN_OK", path, pageCount = pageCount)
      Handler(Looper.getMainLooper()).post {
        result.success(hashMapOf("sessionId" to sessionId, "length" to pageCount))
      }
    } catch (oom: OutOfMemoryError) {
      try { descriptor?.close() } catch (_: Exception) {}
      writeDiagnostic("PDFIUM_OPEN_OOM", path, error = oom.javaClass.simpleName)
      Handler(Looper.getMainLooper()).post {
        result.error("PDFIUM_OPEN_OOM", "PDFium open exhausted memory", null)
      }
    } catch (e: Exception) {
      try { descriptor?.close() } catch (_: Exception) {}
      writeDiagnostic("PDFIUM_OPEN_FAILED", path, error = e.javaClass.simpleName)
      Handler(Looper.getMainLooper()).post {
        result.error("PDFIUM_OPEN_FAILED", e.message, null)
      }
    }
  }

  /** Reads one arbitrary 1-based page from a native PDFium document session. */
  private fun getPdfiumSessionPageText(
    result: Result,
    sessionId: String,
    pageNumber: Int
  ) {
    val document = pdfiumDocuments[sessionId]
    if (document == null) {
      Handler(Looper.getMainLooper()).post {
        result.error("PDFIUM_SESSION_NOT_FOUND", "PDFium session is not available", null)
      }
      return
    }
    val pageCount = document.getPageCount()
    if (pageNumber < 1 || pageNumber > pageCount) {
      Handler(Looper.getMainLooper()).post {
        result.error("PDFIUM_PAGE_OUT_OF_RANGE", "PDFium page is outside document bounds", null)
      }
      return
    }
    val path = pdfiumDocumentPaths[sessionId] ?: ""
    writeDiagnostic("PDFIUM_PAGE_BEGIN", path, pageNumber, pageCount)
    try {
      val page = document.openPage(pageNumber - 1)
      page.use {
        val textPage = page.openTextPage()
        textPage.use {
          val count = textPage.textPageCountChars()
          val text = if (count <= 0) "" else textPage.textPageGetText(0, count).orEmpty()
          writeDiagnostic("PDFIUM_PAGE_OK", path, pageNumber, pageCount)
          Handler(Looper.getMainLooper()).post { result.success(text) }
        }
      }
    } catch (oom: OutOfMemoryError) {
      writeDiagnostic("PDFIUM_PAGE_OOM", path, pageNumber, pageCount, oom.javaClass.simpleName)
      Handler(Looper.getMainLooper()).post {
        result.error("PDFIUM_PAGE_OOM", "PDFium page extraction exhausted memory", null)
      }
    } catch (e: Exception) {
      writeDiagnostic("PDFIUM_PAGE_FAILED", path, pageNumber, pageCount, e.javaClass.simpleName)
      Handler(Looper.getMainLooper()).post {
        result.error("PDFIUM_PAGE_FAILED", e.message, null)
      }
    }
  }

  private fun closePdfiumSession(result: Result, sessionId: String) {
    val document = pdfiumDocuments.remove(sessionId)
    val path = pdfiumDocumentPaths.remove(sessionId) ?: ""
    val pageCount = try { document?.getPageCount() ?: 0 } catch (_: Exception) { 0 }
    try { document?.close() } catch (_: Exception) {}
    writeDiagnostic("PDFIUM_SESSION_CLOSED", path, pageCount = pageCount)
    Handler(Looper.getMainLooper()).post { result.success(true) }
  }

  private fun getLastDiagnostic(result: Result) {
    val file = File(applicationContext.filesDir, diagnosticFileName)
    if (!file.exists()) {
      Handler(Looper.getMainLooper()).post { result.success(null) }
      return
    }
    val values = hashMapOf<String, Any>()
    file.readLines().forEach { line ->
      val separator = line.indexOf('=')
      if (separator <= 0) return@forEach
      val key = line.substring(0, separator)
      val value = line.substring(separator + 1)
      values[key] = value.toLongOrNull() ?: value
    }
    Handler(Looper.getMainLooper()).post { result.success(values) }
  }

  private fun writeDiagnostic(
    stage: String,
    path: String,
    pageNumber: Int = 0,
    pageCount: Int = 0,
    error: String = ""
  ) {
    try {
      val runtime = Runtime.getRuntime()
      val usedHeap = runtime.totalMemory() - runtime.freeMemory()
      val source = if (path.isBlank()) null else File(path)
      val payload = listOf(
        "stage=$stage",
        "timestamp_ms=${System.currentTimeMillis()}",
        "page_number=$pageNumber",
        "page_count=$pageCount",
        "file_bytes=${source?.takeIf { it.exists() }?.length() ?: 0L}",
        "heap_used_bytes=$usedHeap",
        "heap_total_bytes=${runtime.totalMemory()}",
        "heap_max_bytes=${runtime.maxMemory()}",
        "error=$error"
      ).joinToString("\n") + "\n"
      val target = File(applicationContext.filesDir, diagnosticFileName)
      val temp = File(applicationContext.filesDir, diagnosticFileName + ".tmp")
      temp.writeText(payload)
      if (!temp.renameTo(target)) {
        target.writeText(payload)
        temp.delete()
      }
    } catch (_: Throwable) {
      // Diagnostics are best effort and must never become the failure source.
    }
  }

  /**
   * Splits a string of keywords into a list of strings.
   */
  private fun splitKeywords(keywordsString: String?): List<String>? {
    if (keywordsString == null) {
      return null
    }
    val keywords = keywordsString.split(",").toMutableList()
    for (i in keywords.indices) {
      var keyword = keywords[i]
      keyword = keyword.dropWhile { it == ' ' }
      keyword = keyword.dropLastWhile { it == ' ' }
      keywords[i] = keyword
    }
    return keywords
  }

  /**
    Gets the text  of a document page, given its number.
   */
  private fun getDocPageText(result: Result, path: String, pageNumber: Int, password: String) {
    getDoc(result, path, password)?.use { doc ->
      val stripper = PDFTextStripper();
      stripper.startPage = pageNumber
      stripper.endPage = pageNumber
      val text = stripper.getText(doc)
      doc.close()
      Handler(Looper.getMainLooper()).post {
        result.success(text)
      }
    }
  }

  /**
  Gets the text of the entire document.
  In order to improve the performance, it only retrieves the pages that are currently missing.
   */
  private fun getDocText(result: Result, path: String, missingPagesNumbers: List<Int>, password: String) {
    getDoc(result, path, password)?.use { doc ->
      val missingPagesTexts = arrayListOf<String>()
      val stripper = PDFTextStripper();
      missingPagesNumbers.forEach {
        stripper.startPage = it
        stripper.endPage = it
        missingPagesTexts.add(stripper.getText(doc))
      }
      doc.close()
      Handler(Looper.getMainLooper()).post {
        result.success(missingPagesTexts)
      }
    }
  }

  /**
  Gets a PDF document, given its path.
   */
  private fun getDoc(result: Result, path: String, password: String = ""): PDDocument? {
    writeDiagnostic("OPEN_BEGIN", path)
    return try {
      val memoryUsageSetting = MemoryUsageSetting.setupTempFileOnly()
        .setTempDir(applicationContext.cacheDir)
      val doc = PDDocument.load(File(path), password, memoryUsageSetting)
      writeDiagnostic("OPEN_OK", path, pageCount = doc.numberOfPages)
      doc
    } catch (oom: OutOfMemoryError) {
      writeDiagnostic("OPEN_OOM", path, error = oom.javaClass.simpleName)
      Handler(Looper.getMainLooper()).post {
        result.error("PDF_OPEN_OOM", "PDF open exhausted memory", null)
      }
      null
    } catch (e: Exception) {
      writeDiagnostic("OPEN_FAILED", path, error = e.javaClass.simpleName)
      Handler(Looper.getMainLooper()).post {
        result.error("INVALID_PATH",
                "File path or password (in case of encrypted document) is invalid",
                null)
      }
      null
    }
  }
}
