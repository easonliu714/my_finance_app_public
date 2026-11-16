package me.movenext.flutter_pdf_text

import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

@RunWith(AndroidJUnit4::class)
class InvoiceAwardNoBackupFloorCandidateInstrumentedTest {
  @Test fun alteredSchemaAndTriggerFailClosed() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val store = InvoiceAwardNoBackupFloorCandidate(context)
    val path = store.isolatedPathForTest()
    path.delete()
    try {
      store.initializeForIsolatedTest(20)
      SQLiteDatabase.openDatabase(path.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
        db.execSQL("CREATE TRIGGER malicious AFTER UPDATE ON floor BEGIN DELETE FROM floor; END")
      }
      assertNull(store.readFloor())
      assertFalse(store.compareAndAdvance(20, 21))
      try {
        store.initializeForIsolatedTest(20)
        fail("Existing trigger must not be trusted")
      } catch (_: IllegalStateException) { }
      SQLiteDatabase.openDatabase(path.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
        db.execSQL("DROP TRIGGER malicious")
        db.execSQL("ALTER TABLE floor ADD COLUMN unexpected INTEGER")
      }
      assertNull(store.readFloor())
      assertFalse(store.compareAndAdvance(20, 21))
    } finally { path.delete() }
  }

  @Test fun noBackupDiskReopenAndIndependentConnectionsRace() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val store = InvoiceAwardNoBackupFloorCandidate(context)
    val path = store.isolatedPathForTest()
    path.delete()
    assertNull(store.readFloor())
    store.initializeForIsolatedTest(10)
    assertTrue(path.canonicalPath.startsWith(context.noBackupFilesDir.canonicalPath + "/"))
    assertEquals(10L, InvoiceAwardNoBackupFloorCandidate(context).readFloor())
    val start = CountDownLatch(1)
    val wins = AtomicInteger()
    val workers = (1..2).map {
      thread {
        start.await()
        if (InvoiceAwardNoBackupFloorCandidate(context).compareAndAdvance(10, 11)) wins.incrementAndGet()
      }
    }
    start.countDown()
    workers.forEach { it.join() }
    assertEquals(1, wins.get())
    assertEquals(11L, InvoiceAwardNoBackupFloorCandidate(context).readFloor())
    assertFalse(store.compareAndAdvance(10, 12))
    assertFalse(store.canActivateProduction())
    path.delete()
  }
}
