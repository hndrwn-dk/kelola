package com.tursinalabs.kelola

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class KelolaWidgetPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.tursinalabs.kelola/widget")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "update") {
            result.notImplemented()
            return
        }
        val ctx = context
        if (ctx == null) {
            result.error("no_context", "widget plugin has no context", null)
            return
        }
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        ctx.getSharedPreferences(StatusWidgetProvider.PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean("enabled", args["enabled"] == true)
            .putString("hostId", args["hostId"] as? String)
            .putString("alias", args["alias"] as? String)
            .putInt("failedCount", (args["failedCount"] as? Number)?.toInt() ?: 0)
            .putLong(
                "refreshedAtMillis",
                (args["refreshedAtMillis"] as? Number)?.toLong() ?: 0L,
            )
            .apply()
        StatusWidgetProvider.refreshAll(ctx)
        result.success(null)
    }
}
