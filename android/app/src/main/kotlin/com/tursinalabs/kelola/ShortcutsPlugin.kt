package com.tursinalabs.kelola

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ShortcutsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: android.content.Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.tursinalabs.kelola/shortcuts",
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "set") {
            result.notImplemented()
            return
        }
        val ctx = context
        if (ctx == null) {
            result.error("no_context", "shortcuts plugin has no context", null)
            return
        }
        val manager = ctx.getSystemService(ShortcutManager::class.java)
        val raw = call.arguments as? List<*> ?: emptyList<Any>()
        val shortcuts = raw.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val id = map["id"] as? String ?: return@mapNotNull null
            val label = map["label"] as? String ?: return@mapNotNull null
            val uri = map["uri"] as? String ?: return@mapNotNull null
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                setClass(ctx, MainActivity::class.java)
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            ShortcutInfo.Builder(ctx, id)
                .setShortLabel(label)
                .setLongLabel(label)
                .setIcon(Icon.createWithResource(ctx, R.mipmap.ic_launcher))
                .setIntent(intent)
                .build()
        }
        manager.dynamicShortcuts = shortcuts
        result.success(null)
    }
}
