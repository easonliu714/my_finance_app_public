package me.movenext.flutter_pdf_text

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Best-effort publication wake-up marker for Issue #13.
 *
 * Deliberately performs no network request and starts no Activity. Android may
 * defer the alarm; foreground catch-up is the authority-preserving fallback.
 */
class InvoiceAwardRefreshWakeReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    val target = intent?.getLongExtra(EXTRA_TARGET_MS, -1L) ?: -1L
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putLong(KEY_DUE_TARGET_MS, target)
      .putLong(KEY_RECEIVED_AT_MS, System.currentTimeMillis())
      .apply()
  }

  companion object {
    private const val PREFS = "issue13_invoice_award_scheduler"
    private const val KEY_DUE_TARGET_MS = "due_target_ms"
    private const val KEY_RECEIVED_AT_MS = "received_at_ms"
    private const val EXTRA_TARGET_MS = "target_ms"
    private const val REQUEST_CODE = 1320477
    private const val WINDOW_MS = 15L * 60L * 1000L

    private fun pendingIntent(
      context: Context,
      targetMs: Long,
      flags: Int
    ): PendingIntent {
      val intent = Intent(context, InvoiceAwardRefreshWakeReceiver::class.java)
        .putExtra(EXTRA_TARGET_MS, targetMs)
      return PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        intent,
        flags or PendingIntent.FLAG_IMMUTABLE
      )
    }

    fun schedule(context: Context, triggerAtMillis: Long) {
      val alarm = context.getSystemService(AlarmManager::class.java)
      val operation = pendingIntent(
        context,
        triggerAtMillis,
        PendingIntent.FLAG_UPDATE_CURRENT
      )
      // Best-effort by design: no exact-alarm permission and no wake lock.
      alarm.setWindow(
        AlarmManager.RTC_WAKEUP,
        triggerAtMillis,
        WINDOW_MS,
        operation
      )
    }

    fun cancel(context: Context) {
      val alarm = context.getSystemService(AlarmManager::class.java)
      val existing = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, InvoiceAwardRefreshWakeReceiver::class.java),
        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
      )
      if (existing != null) {
        alarm.cancel(existing)
        existing.cancel()
      }
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .edit()
        .remove(KEY_DUE_TARGET_MS)
        .remove(KEY_RECEIVED_AT_MS)
        .apply()
    }

    fun consume(context: Context): Map<String, Long>? {
      val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      if (!prefs.contains(KEY_RECEIVED_AT_MS)) return null
      val result = hashMapOf(
        "targetMillis" to prefs.getLong(KEY_DUE_TARGET_MS, -1L),
        "receivedAtMillis" to prefs.getLong(KEY_RECEIVED_AT_MS, -1L)
      )
      prefs.edit()
        .remove(KEY_DUE_TARGET_MS)
        .remove(KEY_RECEIVED_AT_MS)
        .apply()
      return result
    }
  }
}
