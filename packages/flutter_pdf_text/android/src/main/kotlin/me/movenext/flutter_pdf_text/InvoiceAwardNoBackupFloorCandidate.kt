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

  /** Reject modified DDL, indexes, views and triggers before trusting any floor bytes. */
  private fun hasExactSchema(db: SQLiteDatabase): Boolean {
    val expected = "CREATE TABLE floor (id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL CHECK(revision >= 0))"
    db.rawQuery("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'", null).use { c ->
      if (!c.moveToFirst()) return false
      if (c.getString(0) != "table" || c.getString(1) != "floor" ||
          c.getString(2) != "floor" || c.getString(3) != expected || c.moveToNext()) return false
    }
    db.rawQuery("PRAGMA table_info(floor)", null).use { c ->
      if (!c.moveToFirst() || c.getString(1) != "id" || c.getString(2) != "INTEGER" ||
          c.getInt(5) != 1 || !c.moveToNext() || c.getString(1) != "revision" ||
          c.getString(2) != "INTEGER" || c.getInt(3) != 1 || c.getInt(5) != 0 ||
          c.moveToNext()) return false
    }
    return true
  }

  fun initializeForIsolatedTest(initialRevision: Long = 0L) {
    require(initialRevision >= 0L)
    val db = SQLiteDatabase.openOrCreateDatabase(isolatedPathForTest(), null)
    try {
      db.beginTransaction()
      try {
        // Match the exact sqlite_master DDL; an existing trusted table is handled by the schema guard.
        if (!db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='floor'", null).use { it.moveToFirst() }) {
          db.execSQL("CREATE TABLE floor (id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL CHECK(revision >= 0))")
        }
        check(hasExactSchema(db)) { "Untrusted floor schema" }
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
      if (!hasExactSchema(db)) return null
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
        if (!hasExactSchema(db)) return false
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
