package com.tursinalabs.kelola

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * specialUse foreground service that keeps SSH local forwards alive and
 * surfaces an ongoing notification with a Stop all action.
 */
class TunnelForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Process death must not resurrect a tunnel-less FGS.
        if (intent == null) {
            stopForegroundService()
            return START_NOT_STICKY
        }
        when (intent.action) {
            ACTION_STOP_ALL -> {
                TunnelPlugin.invokeStopAll()
                return START_NOT_STICKY
            }
            ACTION_STOP -> {
                stopForegroundService()
                return START_NOT_STICKY
            }
            else -> {
                val text = intent.getStringExtra(EXTRA_TEXT)
                    ?: lastText
                    ?: "Tunnels active"
                lastText = text
                ensureChannel()
                val notification = buildNotification(this, text)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    ServiceCompat.startForeground(
                        this,
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        TunnelPlugin.invokeTaskRemoved()
        stopForegroundService()
        super.onTaskRemoved(rootIntent)
    }

    private fun stopForegroundService() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
        lastText = null
    }

    private fun ensureChannel() {
        ensureChannel(this)
    }

    companion object {
        const val CHANNEL_ID = "kelola_tunnels"
        const val NOTIFICATION_ID = 71001
        const val EXTRA_TEXT = "text"
        const val ACTION_START = "com.tursinalabs.kelola.tunnel.START"
        const val ACTION_UPDATE = "com.tursinalabs.kelola.tunnel.UPDATE"
        const val ACTION_STOP = "com.tursinalabs.kelola.tunnel.STOP"
        const val ACTION_STOP_ALL = "com.tursinalabs.kelola.tunnel.STOP_ALL"

        @Volatile
        private var lastText: String? = null

        fun startOrUpdate(context: Context, text: String) {
            lastText = text
            val intent = Intent(context, TunnelForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TEXT, text)
            }
            context.startForegroundService(intent)
        }

        /**
         * Updates notification text while the FGS is already running.
         * Uses [NotificationManager.notify] — never [Context.startForegroundService],
         * which can crash on Android 12+ when called from the background.
         */
        fun update(context: Context, text: String) {
            lastText = text
            ensureChannel(context)
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.notify(NOTIFICATION_ID, buildNotification(context, text))
        }

        fun stop(context: Context) {
            val intent = Intent(context, TunnelForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Tunnels",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Active SSH local port forwards"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        private fun buildNotification(context: Context, text: String): Notification {
            val stopIntent = Intent(context, TunnelForegroundService::class.java).apply {
                action = ACTION_STOP_ALL
            }
            val stopPending = PendingIntent.getService(
                context,
                0,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentPending = if (launchIntent != null) {
                PendingIntent.getActivity(
                    context,
                    1,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } else {
                null
            }
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_tunnel_notification)
                .setContentTitle("Kelola tunnels")
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setContentIntent(contentPending)
                .addAction(0, "Stop all", stopPending)
                .build()
        }
    }
}
