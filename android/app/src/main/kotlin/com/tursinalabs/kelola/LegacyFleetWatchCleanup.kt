package com.tursinalabs.kelola

import android.app.NotificationManager
import android.content.Context
import androidx.work.WorkManager

/**
 * Fleet watch is gone, but installs that had it on still hold its hourly job
 * and notification channel. Drop both. A failure here must not stop the app.
 */
object LegacyFleetWatchCleanup {
    const val WORK_NAME = "kelola_fleet_watch"
    const val NOTIFY_CHANNEL = "kelola_fleet"

    fun run(context: Context) {
        runCatching { WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME) }
        runCatching {
            context.getSystemService(NotificationManager::class.java)
                ?.deleteNotificationChannel(NOTIFY_CHANNEL)
        }
    }
}
