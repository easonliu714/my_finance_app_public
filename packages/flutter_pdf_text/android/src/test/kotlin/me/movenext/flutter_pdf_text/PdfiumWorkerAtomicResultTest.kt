package me.movenext.flutter_pdf_text

import java.io.File
import java.io.IOException
import kotlin.io.path.createTempDirectory
import org.junit.Assert.*
import org.junit.Test

class PdfiumWorkerAtomicResultTest {
  @Test fun successfulPublicationReplacesCompleteOldJsonAndCleansTemp() {
    val root = createTempDirectory("worker-atomic-positive-").toFile()
    try {
      val target = File(root, "result.json")
      target.writeText("{\"status\":\"running\"}")
      val complete = "{\"status\":\"complete\",\"matched\":[\"AA00000001\"]}"
      PdfiumWorkerAtomicResult.write(target, complete)
      assertEquals(complete, target.readText())
      assertEquals(listOf("result.json"), root.listFiles()!!.map { it.name })
    } finally { root.deleteRecursively() }
  }

  @Test fun renameFailurePreservesExistingResultAndDeletesTemp() {
    val root = createTempDirectory("worker-atomic-negative-").toFile()
    try {
      val target = File(root, "result.json")
      val previous = "{\"status\":\"running\",\"stage\":\"PDFIUM_OPEN_WAIT\"}"
      target.writeText(previous)
      try {
        PdfiumWorkerAtomicResult.write(target, "{\"status\":\"complete\"}") { _, _ -> false }
        fail("failed rename promoted a complete result")
      } catch (error: IOException) {
        assertEquals("PDFIUM_WORKER_RESULT_ATOMIC_RENAME_FAILED", error.message)
      }
      assertEquals(previous, target.readText())
      assertEquals(listOf("result.json"), root.listFiles()!!.map { it.name })
    } finally { root.deleteRecursively() }
  }

  @Test fun failedFirstPublicationDoesNotCreateResultOrLeaveTemp() {
    val root = createTempDirectory("worker-atomic-first-failure-").toFile()
    try {
      val target = File(root, "result.json")
      try {
        PdfiumWorkerAtomicResult.write(target, "{\"status\":\"complete\"}") { _, _ -> false }
        fail("failed rename published a new result")
      } catch (error: IOException) {
        assertEquals("PDFIUM_WORKER_RESULT_ATOMIC_RENAME_FAILED", error.message)
      }
      assertFalse(target.exists())
      assertTrue(root.listFiles()!!.isEmpty())
    } finally { root.deleteRecursively() }
  }
}
