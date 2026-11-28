package me.movenext.flutter_pdf_text

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class LabL1DrawResultPathTest {
  private val id = "123456789"
  private val name = "platform_probe_$id.json"

  private fun rejects(block: () -> Unit) {
    try {
      block()
      fail("Expected invalid receipt path")
    } catch (error: IllegalStateException) {
      assertEquals("L1_OWNER_DRAW_RESULT_PATH_INVALID", error.message)
    }
  }

  private fun fixture(block: (File, File) -> Unit) {
    val root = Files.createTempDirectory("draw-result-root").toFile().canonicalFile
    try {
      val lab = File(root, "issue13_cloud500_diag").apply { mkdir() }
      block(root, lab)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test fun exactNewPrivateReceiptIsAdmittedWithoutWriting() = fixture { root, lab ->
    val target = File(lab, name)
    assertEquals(target, LabL1DrawResultPath.requireNew(root, target.path, id))
    assertFalse(target.exists())
  }

  @Test fun wrongRequestNameOrDirectoryCannotCreateReceipt() = fixture { root, lab ->
    val sibling = File(root, "other").apply { mkdir() }
    for (path in listOf(File(root, name), File(sibling, name), File(lab, "wrong.json"),
        File(lab, "platform_probe_999.json"), File(lab, "../$name"))) {
      rejects { LabL1DrawResultPath.requireNew(root, path.path, id) }
      assertFalse(path.exists())
    }
    rejects { LabL1DrawResultPath.requireNew(root, File(lab, name).path, "../bad") }
    rejects { LabL1DrawResultPath.requireNew(root, name, id) }
  }

  @Test fun existingReceiptAndDanglingLinkAreNotOverwritten() = fixture { root, lab ->
    val target = File(lab, name).apply { writeText("retain") }
    rejects { LabL1DrawResultPath.requireNew(root, target.path, id) }
    assertEquals("retain", target.readText())
    target.delete()
    val missing = File(root, "missing.json")
    Files.createSymbolicLink(target.toPath(), missing.toPath())
    rejects { LabL1DrawResultPath.requireNew(root, target.path, id) }
    assertFalse(missing.exists())
    Files.delete(target.toPath())
  }

  @Test fun linkedLabDirectoryCannotEscapePrivateCustody() = fixture { root, lab ->
    val other = File(root, "other").apply { mkdir() }
    lab.delete()
    Files.createSymbolicLink(lab.toPath(), other.toPath())
    rejects { LabL1DrawResultPath.requireNew(root, File(lab, name).path, id) }
    assertFalse(File(other, name).exists())
    Files.delete(lab.toPath())
  }
}
