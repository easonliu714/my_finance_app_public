package me.movenext.flutter_pdf_text

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * Isolated Android noBackup candidate, not a production ledger or rollback-proof authority.
 * Never invoked by formal posting or restore. All callers must explicitly initialize a test DB.
 */
internal class InvoiceAwardNoBackupFloorCandidate(private val context: Context) {
  private val file: File
    get() = File(context.noBackupFilesDir, "invoice_award_floor_isolated_v25c.sqlite")

  fun isolatedPathForTest(): File {
    val parent = context.noBackupFilesDir.canonicalFile
    val candidate = file.canonicalFile
    require(candidate.parentFile == parent) { "Floor escaped noBackup directory" }
    return candidate
  }

  fun initializeForIsolatedTest(initialRevision: Long = 0L) {
    require(initialRevision >= 0L)
    val db = SQLiteDatabase.openOrCreateDatabase(isolatedPathForTest(), null)
    try {
      db.beginTransaction()
      try {
        db.execSQL("CREATE TABLE IF NOT EXISTS floor (id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL CHECK(revision >= 0))")
        db.execSQL("INSERT OR IGNORE INTO floor(id,revision) VALUES(1,?)", arrayOf(initialRevision))
        db.setTransactionSuccessful()
      } finally { db.endTransaction() }
    } finally { db.close() }
  }

  /** Missing, corrupt, or non-singleton state is not authority. Never initializes on read. */
  fun readFloor(): Long? {
    val path = isolatedPathForTest()
    if (!path.isFile) return null
    val db = try { SQLiteDatabase.openDatabase(path.path, null, SQLiteDatabase.OPEN_READONLY) }
      catch (_: Exception) { return null }
    try {
      db.rawQuery("SELECT id,revision FROM floor", null).use { cursor ->
        if (!cursor.moveToFirst() || cursor.getLong(0) != 1L) return null
        val value = cursor.getLong(1)
        if (value < 0L || cursor.moveToNext()) return null
        return value
      }
    } catch (_: Exception) { return null }
    finally { db.close() }
  }

  fun compareAndAdvance(expected: Long, next: Long): Boolean {
    if (expected < 0L || next <= expected || !isolatedPathForTest().isFile) return false
    val db = try { SQLiteDatabase.openDatabase(isolatedPathForTest().path, null, SQLiteDatabase.OPEN_READWRITE) }
      catch (_: Exception) { return false }
    try {
      db.beginTransaction()
      try {
        db.rawQuery("SELECT id,revision FROM floor", null).use { cursor ->
          if (!cursor.moveToFirst() || cursor.getLong(0) != 1L ||
              cursor.getLong(1) != expected || cursor.moveToNext()) return false
        }
        db.execSQL("UPDATE floor SET revision=? WHERE id=1 AND revision=?", arrayOf(next, expected))
        val changed = db.rawQuery("SELECT changes()", null).use { cursor ->
          cursor.moveToFirst() && cursor.getLong(0) == 1L
        }
        if (changed) db.setTransactionSuccessful()
        return changed
      } finally { db.endTransaction() }
    } catch (_: Exception) { return false }
    finally { db.close() }
  }

  fun canActivateProduction(): Boolean = false
}
