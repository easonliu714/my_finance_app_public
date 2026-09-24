package me.movenext.flutter_pdf_text

import android.content.Context
import android.os.Handler
import android.os.Looper
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
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/** PdfTextPlugin */
class PdfTextPlugin: FlutterPlugin, MethodCallHandler {

  private lateinit var applicationContext: Context
  private val openDocuments = ConcurrentHashMap<String, PDDocument>()

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = flutterPluginBinding.applicationContext
    val channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pdf_text")
    channel.setMethodCallHandler(this)
    PDFBoxResourceLoader.init(applicationContext)
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
    try {
      val stripper = PDFTextStripper()
      stripper.startPage = pageNumber
      stripper.endPage = pageNumber
      val text = stripper.getText(doc)
      Handler(Looper.getMainLooper()).post { result.success(text) }
    } catch (e: Exception) {
      Handler(Looper.getMainLooper()).post {
        result.error("PDF_SESSION_PAGE_FAILED", e.message, null)
      }
    }
  }

  /** Closes the bounded native document session even when Dart parsing fails. */
  private fun closeDocSession(result: Result, sessionId: String) {
    val doc = openDocuments.remove(sessionId)
    try { doc?.close() } catch (_: Exception) {}
    Handler(Looper.getMainLooper()).post { result.success(true) }
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
    return try {
      val memoryUsageSetting = MemoryUsageSetting.setupTempFileOnly()
        .setTempDir(applicationContext.cacheDir)
      PDDocument.load(File(path), password, memoryUsageSetting)
    } catch (e: Exception) {
      Handler(Looper.getMainLooper()).post {
        result.error("INVALID_PATH",
                "File path or password (in case of encrypted document) is invalid",
                null)
      }
      null
    }
  }
}
