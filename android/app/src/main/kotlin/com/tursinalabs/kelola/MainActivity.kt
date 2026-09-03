package com.tursinalabs.kelola

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var links: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(HardwareSignerPlugin())
        flutterEngine.plugins.add(KelolaWidgetPlugin())
        links = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tursinalabs.kelola/links",
        )
        links?.setMethodCallHandler { call, result ->
            if (call.method == "get") {
                result.success(intent?.data?.toString())
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.data?.toString()?.let { links?.invokeMethod("opened", it) }
    }
}
