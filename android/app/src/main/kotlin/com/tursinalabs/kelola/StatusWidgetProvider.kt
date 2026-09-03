package com.tursinalabs.kelola

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class StatusWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context))
        }
    }

    companion object {
        const val PREFS = "kelola_widget"

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, StatusWidgetProvider::class.java),
            )
            if (ids.isEmpty()) {
                return
            }
            val views = build(context)
            for (id in ids) {
                manager.updateAppWidget(id, views)
            }
        }

        fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val enabled = prefs.getBoolean("enabled", false)
            val alias = prefs.getString("alias", "") ?: ""
            val failed = prefs.getInt("failedCount", 0)
            val hostId = prefs.getString("hostId", "") ?: ""
            val refreshedAt = prefs.getLong("refreshedAtMillis", 0L)
            val views = RemoteViews(context.packageName, R.layout.status_widget)
            if (!enabled) {
                views.setTextViewText(R.id.widget_alias, "Widget off")
                views.setTextViewText(R.id.widget_meta, "Enable in Kelola")
            } else if (alias.isEmpty()) {
                views.setTextViewText(R.id.widget_alias, "No hosts")
                views.setTextViewText(R.id.widget_meta, "Last refresh only")
            } else {
                views.setTextViewText(R.id.widget_alias, alias)
                views.setTextViewText(
                    R.id.widget_meta,
                    "$failed failed · ${ageLabel(refreshedAt)}",
                )
            }
            val uri = if (hostId.isNotEmpty()) {
                Uri.parse("kelola://host/$hostId/incident")
            } else {
                Uri.parse("kelola://host")
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = uri
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(context, 0, intent, flags),
            )
            return views
        }

        fun ageLabel(millis: Long): String {
            if (millis <= 0L) {
                return "never"
            }
            val minutes = (System.currentTimeMillis() - millis) / 60000L
            if (minutes < 1L) {
                return "just now"
            }
            if (minutes < 60L) {
                return "${minutes}m ago"
            }
            val hours = minutes / 60L
            if (hours < 24L) {
                return "${hours}h ago"
            }
            return "${hours / 24L}d ago"
        }
    }
}
