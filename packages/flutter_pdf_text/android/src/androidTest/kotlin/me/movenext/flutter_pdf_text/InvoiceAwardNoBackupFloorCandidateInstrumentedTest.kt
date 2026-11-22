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
import java.io.File
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

  @Test fun malformedSqliteStorageClassCannotAuthorizeRestoreOrCas() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val store = InvoiceAwardNoBackupFloorCandidate(context)
    val path = store.isolatedPathForTest()
    path.delete()
    try {
      store.initializeForIsolatedTest(80)
      assertEquals(80L, store.readFloor())
      assertTrue(store.isRestoredSnapshotCurrentForIsolatedTest(80L, true))

      // Exact same DDL accepts these values: INTEGER affinity is not STRICT.
      // A coercing Cursor.getLong() must never attest a malformed revision.
      for ((literal, storageClass) in listOf(
        "80.75" to "real",
        "'invalid'" to "text",
        "X'3830'" to "blob"
      )) {
        SQLiteDatabase.openDatabase(path.path, null,
          SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
          db.execSQL("UPDATE floor SET revision=$literal WHERE id=1")
          db.rawQuery("SELECT typeof(revision) FROM floor", null).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(storageClass, cursor.getString(0))
          }
        }
        assertNull("Malformed $storageClass cannot become floor", store.readFloor())
        for (candidate in listOf(0L, 80L, 81L)) {
          assertFalse(store.isRestoredSnapshotCurrentForIsolatedTest(candidate, true))
          assertFalse(store.compareAndAdvance(candidate, 82L))
        }
        try {
          store.initializeForIsolatedTest(80)
          fail("Reinitialization must reject malformed custody")
        } catch (_: IllegalStateException) { }
        SQLiteDatabase.openDatabase(path.path, null,
          SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
          db.rawQuery("SELECT typeof(revision), quote(revision) FROM floor", null).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(storageClass, cursor.getString(0))
            assertEquals(literal, cursor.getString(1))
            assertFalse(cursor.moveToNext())
          }
        }
      }

      // Only the disposable test fixture repairs its data. Valid INTEGER
      // custody and monotonic CAS must remain functional afterward.
      SQLiteDatabase.openDatabase(path.path, null,
        SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
        db.execSQL("UPDATE floor SET revision=80 WHERE id=1")
      }
      store.initializeForIsolatedTest(0)
      assertEquals(80L, store.readFloor())
      assertTrue(store.compareAndAdvance(80L, 81L))
      assertFalse(store.isRestoredSnapshotCurrentForIsolatedTest(80L, true))
      assertTrue(store.isRestoredSnapshotCurrentForIsolatedTest(81L, true))
      assertFalse(store.canActivateProduction())
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
      val ready = CountDownLatch(1)
      val received = CountDownLatch(1)
      var reply: Bundle? = null
      var prepareReply: Bundle? = null
      val receiver = Messenger(Handler(Looper.getMainLooper()) { message ->
        when (message.what) {
          PlatformLeaseProbeService.FLOOR_CAS_PREPARE -> {
            prepareReply = message.data
            ready.countDown()
          }
          PlatformLeaseProbeService.FLOOR_CAS_ISOLATED -> {
            reply = message.data
            received.countDown()
          }
        }
        true
      })
      val start = CountDownLatch(1)
      val localReady = CountDownLatch(1)
      var localWon = false
      val local = thread {
        localReady.countDown()
        start.await()
        localWon = InvoiceAwardNoBackupFloorCandidate(context).compareAndAdvance(40, 41)
      }
      assertTrue("Local CAS worker not ready", localReady.await(15, TimeUnit.SECONDS))
      val prepare = Message.obtain(null, PlatformLeaseProbeService.FLOOR_CAS_PREPARE)
      prepare.replyTo = receiver
      prepare.data = Bundle().apply {
        putLong("expected", 40)
        putLong("next", 41)
      }
      sender.send(prepare)
      assertTrue("Remote CAS worker not ready", ready.await(15, TimeUnit.SECONDS))
      assertTrue("Remote CAS prepare failed", prepareReply?.getBoolean("ready") == true)
      // Both OS-process workers are now parked at explicit gates. The remote
      // gate is released by IPC, immediately followed by the local gate.
      // This proves readiness, not nanosecond-simultaneous CPU scheduling.
      val go = Message.obtain(null, PlatformLeaseProbeService.FLOOR_CAS_GO)
      try { sender.send(go) } finally { start.countDown() }
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

  /**
   * V25-G-52: the remote OS PID actually dies and a fresh service process
   * reopens the same fixed noBackup floor. This does not prove restore
   * anti-rollback or authorize production ledger posting.
   */
  @Test fun isolatedFloorSurvivesRealRemoteProcessDeathAndRestart() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val floor = InvoiceAwardNoBackupFloorCandidate(context)
    val path = floor.isolatedPathForTest()
    path.delete()
    floor.initializeForIsolatedTest(70)
    val intent = Intent().setClassName(context.packageName,
      "me.movenext.flutter_pdf_text.PlatformLeaseProbeService")

    fun bindRemote(): Triple<Messenger, IBinder, ServiceConnection> {
      val connected = CountDownLatch(1)
      var binder: IBinder? = null
      val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
          binder = service
          connected.countDown()
        }
        override fun onServiceDisconnected(name: ComponentName?) { }
      }
      assertTrue("Remote restart bind refused",
        context.bindService(intent, connection, Context.BIND_AUTO_CREATE))
      if (!connected.await(20, TimeUnit.SECONDS) || binder == null) {
        context.unbindService(connection)
        fail("Remote restart bind timeout")
      }
      val liveBinder = binder ?: error("REMOTE_RESTART_BINDER_MISSING")
      return Triple(Messenger(liveBinder), liveBinder, connection)
    }

    fun request(remote: Messenger, command: Int, expected: Long = 0, next: Long = 0): Bundle {
      val received = CountDownLatch(1)
      var reply: Bundle? = null
      val receiver = Messenger(Handler(Looper.getMainLooper()) { message ->
        reply = message.data
        received.countDown()
        true
      })
      val message = Message.obtain(null, command)
      message.replyTo = receiver
      message.data = Bundle().apply {
        putLong("expected", expected)
        putLong("next", next)
      }
      remote.send(message)
      assertTrue("Remote restart command timeout: $command",
        received.await(15, TimeUnit.SECONDS))
      return reply ?: error("REMOTE_RESTART_REPLY_MISSING")
    }

    var firstConnection: ServiceConnection? = null
    var secondConnection: ServiceConnection? = null
    try {
      val (first, firstBinder, connection) = bindRemote()
      firstConnection = connection
      val initial = request(first, PlatformLeaseProbeService.FLOOR_CAS_ISOLATED, 70, 71)
      val oldPid = initial.getInt("pid")
      assertNotEquals(Process.myPid(), oldPid)
      assertEquals(Process.myUid(), initial.getInt("uid"))
      assertTrue("Remote initial CAS failed", initial.getBoolean("advanced"))
      assertEquals(71L, floor.readFloor())

      val died = CountDownLatch(1)
      firstBinder.linkToDeath({ died.countDown() }, 0)
      val termination = request(first, PlatformLeaseProbeService.TERMINATE_ISOLATED_PROCESS)
      assertEquals(oldPid, termination.getInt("pid"))
      assertTrue("Remote process termination not acknowledged",
        termination.getBoolean("terminating"))
      assertTrue("Remote binder never died", died.await(20, TimeUnit.SECONDS))
      context.unbindService(connection)
      firstConnection = null

      val (second, _, newConnection) = bindRemote()
      secondConnection = newConnection
      val stale = request(second, PlatformLeaseProbeService.FLOOR_CAS_ISOLATED, 70, 72)
      assertNotEquals("Restart must have a new Android OS PID", oldPid, stale.getInt("pid"))
      assertEquals(Process.myUid(), stale.getInt("uid"))
      assertFalse("Stale revision accepted after process restart", stale.getBoolean("advanced"))
      assertEquals(71L, stale.getLong("floor"))
      assertEquals(71L, floor.readFloor())
      assertTrue("Fresh revision CAS must still work",
        request(second, PlatformLeaseProbeService.FLOOR_CAS_ISOLATED, 71, 72)
          .getBoolean("advanced"))
      assertEquals(72L, floor.readFloor())
      println("V25_G_52_PROCESS_RESTART old=$oldPid new=${stale.getInt("pid")} durable=true stale_rejected=true")
    } finally {
      secondConnection?.let { context.unbindService(it) }
      firstConnection?.let { context.unbindService(it) }
      path.delete()
    }
  }

  /**
   * V25-H: actual on-disk backup/restore of a disposable ledger-like SQLite
   * file MUST NOT roll back the separately stored noBackup floor. This is
   * a narrowly scoped data rollback regression, not FullRestoreService or
   * hardware-backed anti-rollback integration.
   */
  @Test fun restoredOldLedgerSnapshotCannotReviveStaleFloor() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val floor = InvoiceAwardNoBackupFloorCandidate(context)
    val floorPath = floor.isolatedPathForTest()
    val nonce = System.nanoTime().toString()
    val ledgerPath = File(context.cacheDir, "pr45-v25h-ledger-$nonce.sqlite")
    val backupPath = File(context.cacheDir, "pr45-v25h-old-ledger-$nonce.sqlite")
    floorPath.delete()
    try {
      // Real SQLite file in cache: never touch the canonical ledger.
      assertNotEquals(floorPath.canonicalPath, ledgerPath.canonicalPath)
      SQLiteDatabase.openDatabase(ledgerPath.path, null,
        SQLiteDatabase.CREATE_IF_NECESSARY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
        db.execSQL("CREATE TABLE restored_snapshot (revision INTEGER NOT NULL)")
        db.execSQL("INSERT INTO restored_snapshot(revision) VALUES(80)")
      }
      // Capture a physically separate old backup only after SQLite closes.
      ledgerPath.copyTo(backupPath, overwrite = false)
      floor.initializeForIsolatedTest(80)
      assertTrue(floor.isRestoredSnapshotCurrentForIsolatedTest(80L, true))
      assertFalse(floor.isRestoredSnapshotCurrentForIsolatedTest(80L, false))
      assertFalse(floor.isRestoredSnapshotCurrentForIsolatedTest(null, true))

      // A legitimate independent floor move happens after backup capture.
      assertTrue(floor.compareAndAdvance(80, 81))
      assertEquals(81L, floor.readFloor())
      SQLiteDatabase.openDatabase(ledgerPath.path, null,
        SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
        db.execSQL("UPDATE restored_snapshot SET revision=81")
      }

      // Simulate restoring ONLY the old ledger; noBackup floor remains 81.
      backupPath.copyTo(ledgerPath, overwrite = true)
      val oldRevision = SQLiteDatabase.openDatabase(ledgerPath.path, null,
        SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
        db.rawQuery("SELECT revision FROM restored_snapshot", null).use { cursor ->
          assertTrue(cursor.moveToFirst())
          val value = cursor.getLong(0)
          assertFalse(cursor.moveToNext())
          value
        }
      }
      assertEquals(80L, oldRevision)
      assertEquals(81L, floor.readFloor())
      assertFalse("Old ledger snapshot may not re-authorize a stale floor",
        floor.isRestoredSnapshotCurrentForIsolatedTest(oldRevision, true))
      assertFalse("Old ledger snapshot cannot CAS the independent floor",
        floor.compareAndAdvance(oldRevision, 82))
      assertFalse("Future or forged restored revision cannot become current",
        floor.isRestoredSnapshotCurrentForIsolatedTest(82L, true))
      assertTrue(floor.isRestoredSnapshotCurrentForIsolatedTest(81L, true))
      assertFalse(floor.canActivateProduction())

      // If the supposed independent floor disappears, even an equal
      // restored revision is NOT sufficient evidence to authorize reuse.
      floorPath.delete()
      assertFalse(floor.isRestoredSnapshotCurrentForIsolatedTest(81L, true))
      println("V25_H_52_LEDGER_ONLY_RESTORE_REPLAY_REJECTED floor=81 restored=80")
    } finally {
      floorPath.delete()
      ledgerPath.delete()
      backupPath.delete()
    }
  }

}
