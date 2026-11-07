package me.movenext.flutter_pdf_text

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.pm.ApplicationInfo
import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Synthetic Android 15 foreground-service startup contract.
 *
 * No official PDF, ledger, network, or persisted application data is used.
 * The Platform service must register its channel itself before the first
 * startForeground; prior Pdfium service startup cannot be assumed.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformPdfCandidateWorkerServiceNotificationChannelTest {
  private val channelId = "cloud_award_pdf_worker"

  private fun allowDebugDiagnostics(service: Service) {
    service.applicationInfo.flags =
      service.applicationInfo.flags or ApplicationInfo.FLAG_DEBUGGABLE
  }

  private fun syntheticStartIntent(service: Service): Intent =
    Intent(service, PlatformPdfCandidateWorkerService::class.java)

  @Test
  fun freshInstallRegistersChannelBeforeFirstForegroundStart() {
    val service = Robolectric
      .buildService(PlatformPdfCandidateWorkerService::class.java)
      .create()
      .get()
    val manager = service.getSystemService(NotificationManager::class.java)

    // Existing channel contract applies only to debug diagnostics.
    allowDebugDiagnostics(service)
    assertNull(manager.getNotificationChannel(channelId))
    service.onStartCommand(syntheticStartIntent(service), 0, 1)
    assertNotNull(
      "Platform worker must create the channel before startForeground",
      manager.getNotificationChannel(channelId)
    )
  }

  @Test
  fun preexistingChannelAllowsIdempotentForegroundStart() {
    val service = Robolectric
      .buildService(PlatformPdfCandidateWorkerService::class.java)
      .create()
      .get()
    val manager = service.getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(
      NotificationChannel(
        channelId,
        "Existing synthetic channel",
        NotificationManager.IMPORTANCE_LOW
      )
    )

    allowDebugDiagnostics(service)
    assertEquals(
      Service.START_NOT_STICKY,
      service.onStartCommand(syntheticStartIntent(service), 0, 2)
    )
    assertNotNull(manager.getNotificationChannel(channelId))
  }
  @Test
  fun releaseFlagsRejectDirectWorkerStartWithoutNotification() {
    val service = Robolectric
      .buildService(PlatformPdfCandidateWorkerService::class.java)
      .create()
      .get()
    service.applicationInfo.flags =
      service.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE.inv()
    val manager = service.getSystemService(NotificationManager::class.java)
    assertEquals(
      Service.START_NOT_STICKY,
      service.onStartCommand(syntheticStartIntent(service), 0, 3)
    )
    assertNull("Release must not initialize cloud-500 foreground work",
      manager.getNotificationChannel(channelId))
  }

  @Test
  fun productionGateRejectsNonDebuggableFlagsAndAllowsOnlyDebugDiagnostics() {
    assertEquals(true, Cloud500NativeProductionGate.isDeferred(0))
    assertEquals(true, Cloud500NativeProductionGate.isDeferred(0x100))
    assertEquals(false,
      Cloud500NativeProductionGate.isDeferred(ApplicationInfo.FLAG_DEBUGGABLE))
    assertEquals(
      "CLOUD500_PRODUCTION_DEFERRED_OWNER_OPTION_C",
      Cloud500NativeProductionGate.DEFERRED_CODE)
  }
}
