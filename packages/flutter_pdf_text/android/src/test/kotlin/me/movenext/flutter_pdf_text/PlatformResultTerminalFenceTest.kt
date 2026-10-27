package me.movenext.flutter_pdf_text

import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.rules.TemporaryFolder
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Native JVM terminal-status fence; not process-death or Android durability proof. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformResultTerminalFenceTest {
  @get:Rule val folder = TemporaryFolder()

  private fun payload(id: String, status: String) =
    """{"request_id":"$id","status":"$status"}"""

  private fun writer() = PlatformResultAtomicWriter(syncParent = {})

  @Test fun runningToCompleteThenLateRunningIsRejected() {
    val target = folder.newFile("complete.json")
    target.delete()
    writer().write(target.path, payload("A", "running"))
    writer().write(target.path, payload("A", "complete"))
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload("A", "running"))
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun failedTerminalCannotBeReplacedByComplete() {
    val target = folder.newFile("failed.json")
    writer().write(target.path, payload("A", "failed"))
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload("A", "complete"))
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun foreignRequestCannotOverwriteExistingRunning() {
    val target = folder.newFile("foreign.json")
    writer().write(target.path, payload("A", "running"))
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload("B", "running"))
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun malformedOrUnknownPriorStateFailsClosed() {
    val target = folder.newFile("unknown.json")
    target.writeText("not-json")
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload("A", "running"))
    }
    assertEquals("not-json", target.readText())
    target.writeText(payload("A", "unexpected"))
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload("A", "failed"))
    }
    assertEquals(payload("A", "unexpected"), target.readText())
  }

  @Test fun symlinkedResultTargetIsNotAccepted() {
    val dir = folder.newFolder("symlink")
    val trusted = dir.resolve("trusted.json")
    trusted.writeText(payload("A", "running"))
    val alias = dir.toPath().resolve("alias.json")
    Files.createSymbolicLink(alias, trusted.toPath())
    assertThrows(IOException::class.java) {
      writer().write(alias.toString(), payload("A", "complete"))
    }
    assertEquals(payload("A", "running"), trusted.readText())
  }

  @Test fun invalidIncomingCannotCreateAResult() {
    val target = folder.root.resolve("new.json")
    assertThrows(IOException::class.java) {
      writer().write(target.path, """{"request_id":"","status":"complete"}""")
    }
    assertFalse(target.exists())
  }

  @Test fun fsyncAmbiguityCannotAuthorizeFailureOverwrite() {
    val target = folder.root.resolve("ambiguous.json")
    val faulty = PlatformResultAtomicWriter(
      syncParent = { throw IOException("INJECTED_PARENT_FSYNC_FAILURE") })
    assertThrows(IOException::class.java) {
      faulty.write(target.path, payload("A", "complete"))
    }
    val afterMove = target.readText()
    assertEquals(payload("A", "complete"), afterMove)
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload("A", "failed"))
    }
    assertEquals(afterMove, target.readText())
  }
}
