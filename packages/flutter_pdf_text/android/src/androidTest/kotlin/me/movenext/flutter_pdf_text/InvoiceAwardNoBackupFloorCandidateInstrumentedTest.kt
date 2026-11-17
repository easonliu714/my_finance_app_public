package me.movenext.flutter_pdf_text

import android.database.sqlite.SQLiteDatabase
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import java.util.concurrent.TimeUnit
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
      SQLiteDatabase.openDatabase(path.path, null,
        SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
        db.execSQL("CREATE TRIGGER malicious AFTER UPDATE ON floor BEGIN DELETE FROM floor; END")
      }
      assertNull(store.readFloor())
      assertFalse(store.compareAndAdvance(20, 21))
      try {
        store.initializeForIsolatedTest(20)
        fail("Existing trigger must not be trusted")
      } catch (_: IllegalStateException) { }
      SQLiteDatabase.openDatabase(path.path, null,
        SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
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
    // Reinitialization of an already trusted floor must preserve the monotonic revision.
    store.initializeForIsolatedTest(0)
    assertEquals(10L, store.readFloor())
    assertTrue(path.canonicalPath.startsWith(context.noBackupFilesDir.canonicalPath + "/"))
    assertEquals(10L, InvoiceAwardNoBackupFloorCandidate(context).readFloor())
    // API35 must not inject android_metadata into this numeric-only floor DB.
    SQLiteDatabase.openDatabase(path.path, null,
      SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
      db.rawQuery("SELECT name FROM sqlite_master WHERE name='android_metadata'", null).use { cursor ->
        assertFalse(cursor.moveToFirst())
      }
    }
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
    // Even an otherwise valid-looking system metadata table inserted by an
    // external database opener must not silently be accepted as trusted DDL.
    SQLiteDatabase.openDatabase(path.path, null,
      SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
      db.execSQL("CREATE TABLE android_metadata (locale TEXT)")
    }
    assertNull(store.readFloor())
    assertFalse(store.compareAndAdvance(11, 12))
    assertFalse(store.canActivateProduction())
    path.delete()
  }
  /**
   * V25-E-52: the existing debug-only non-exported lease probe runs under a
   * distinct Android OS PID and the same app UID. Both actors update the
   * identical fixed noBackup SQLite file; no caller-controlled pathname.
   * This is cross-PID CAS evidence, not process-death or restore authority.
   */
  @Test fun independentAndroidPidCompetesForSameNoBackupFloor() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val floor = InvoiceAwardNoBackupFloorCandidate(context)
    val path = floor.isolatedPathForTest()
    path.delete()
    floor.initializeForIsolatedTest(40)
    val connected = CountDownLatch(1)
    var remote: Messenger? = null
    val connection = object : ServiceConnection {
      override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
        if (binder != null) remote = Messenger(binder)
        connected.countDown()
      }
      override fun onServiceDisconnected(name: ComponentName?) { remote = null }
    }
    val intent = Intent().setClassName(context.packageName,
      "me.movenext.flutter_pdf_text.PlatformLeaseProbeService")
    assertTrue(context.bindService(intent, connection, Context.BIND_AUTO_CREATE))
    try {
      assertTrue("Cross-PID floor service bind timeout", connected.await(15, TimeUnit.SECONDS))
      val sender = remote ?: error("CROSS_PID_FLOOR_BINDER_MISSING")
      val received = CountDownLatch(1)
      var reply: Bundle? = null
      val receiver = Messenger(Handler(Looper.getMainLooper()) { message ->
        reply = message.data
        received.countDown()
        true
      })
      val start = CountDownLatch(1)
      var localWon = false
      val local = thread {
        start.await()
        localWon = InvoiceAwardNoBackupFloorCandidate(context).compareAndAdvance(40, 41)
      }
      val request = Message.obtain(null, PlatformLeaseProbeService.FLOOR_CAS_ISOLATED)
      request.replyTo = receiver
      request.data = Bundle().apply {
        putLong("expected", 40)
        putLong("next", 41)
      }
      try {
        sender.send(request)
      } finally {
        start.countDown()
      }
      assertTrue("Cross-PID floor CAS reply timeout", received.await(15, TimeUnit.SECONDS))
      local.join(15000)
      assertFalse("Local CAS worker hung", local.isAlive)
      val response = reply ?: error("CROSS_PID_FLOOR_REPLY_MISSING")
      assertNotEquals("Remote floor CAS must use another Android PID",
        Process.myPid(), response.getInt("pid"))
      assertEquals("Remote floor CAS must share app UID",
        Process.myUid(), response.getInt("uid"))
      assertFalse("Remote floor CAS error: ${response.getString("error")}",
        response.containsKey("error"))
      assertEquals("Exactly one OS process must win CAS", 1,
        (if (localWon) 1 else 0) + (if (response.getBoolean("advanced")) 1 else 0))
      assertEquals(41L, InvoiceAwardNoBackupFloorCandidate(context).readFloor())
      assertFalse(floor.compareAndAdvance(40, 42))
      println("V25_E_52_CROSS_PID_FLOOR_CAS local=${Process.myPid()} remote=${response.getInt("pid")} single_winner=true")
    } finally {
      context.unbindService(connection)
      path.delete()
    }
  }

}
