package com.tursinalabs.kelola

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.TimeUnit

class FleetWatchPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        instance = this
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        if (instance === this) {
            instance = null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("no_context", "Fleet watch plugin has no context", null)
            return
        }
        when (call.method) {
            "requestPostNotifications" -> requestNotifications(result)
            "notify" -> {
                val hostId = call.argument<String>("hostId") ?: ""
                val title = call.argument<String>("title") ?: "Kelola"
                val body = call.argument<String>("body") ?: ""
                notify(ctx, hostId, title, body)
                result.success(null)
            }
            "schedule" -> {
                schedule(ctx)
                result.success(null)
            }
            "cancel" -> {
                WorkManager.getInstance(ctx).cancelUniqueWork(WORK_NAME)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_POST_NOTIFICATIONS) return false
        val pending = permissionResult ?: return true
        permissionResult = null
        pending.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        return true
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        permissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    companion object {
        const val CHANNEL = "kelola/fleet_watch"
        const val NOTIFY_CHANNEL = "kelola_fleet"
        const val WORK_NAME = "kelola_fleet_watch"
        private const val REQUEST_POST_NOTIFICATIONS = 71003

        @Volatile
        private var instance: FleetWatchPlugin? = null

        fun requestTick() {
            instance?.channel?.invokeMethod("tick", null)
        }

        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val work = PeriodicWorkRequestBuilder<FleetWatchWorker>(1, TimeUnit.HOURS)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                work,
            )
        }

        fun notify(context: Context, hostId: String, title: String, body: String) {
            ensureChannel(context)
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val launch = PendingIntent.getActivity(
                context,
                hostId.hashCode(),
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(context, NOTIFY_CHANNEL)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(launch)
                .setAutoCancel(true)
                .build()
            manager.notify(70000 + (hostId.hashCode() and 0xffff), notification)
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(NOTIFY_CHANNEL) != null) return
            val channel = NotificationChannel(
                NOTIFY_CHANNEL,
                "Fleet watch",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Local alerts when a watched host changes state"
                setShowBadge(true)
            }
            manager.createNotificationChannel(channel)
        }
    }
}

class FleetWatchWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {
    override fun doWork(): Result {
        FleetWatchPlugin.requestTick()
        return Result.success()
    }
}
