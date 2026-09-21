package com.tursinalabs.kelola

import android.content.Context
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AppLockPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: FragmentActivity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canAuthenticate" -> result.success(canAuthenticate())
            "authenticate" -> authenticate(result)
            "setSecure" -> {
                setSecure(call.argument<Boolean>("secure") == true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun authenticators(): Int {
        return BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL
    }

    private fun canAuthenticate(): Boolean {
        val ctx = context ?: return false
        val status = BiometricManager.from(ctx).canAuthenticate(authenticators())
        return status == BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun authenticate(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("no_activity", "authenticate requires an activity", null)
            return
        }
        if (!canAuthenticate()) {
            result.error("unavailable", "no device credential", null)
            return
        }
        var replied = false
        fun reply(value: Any?) {
            if (replied) {
                return
            }
            replied = true
            result.success(value)
        }
        val prompt = BiometricPrompt(
            act,
            ContextCompat.getMainExecutor(act),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResult: BiometricPrompt.AuthenticationResult,
                ) {
                    reply(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_CANCELED,
                        -> reply(false)
                        else -> {
                            if (replied) {
                                return
                            }
                            replied = true
                            result.error("unavailable", errString.toString(), null)
                        }
                    }
                }
            },
        )
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle("Unlock Kelola")
                .setAllowedAuthenticators(authenticators())
                .build(),
        )
    }

    private fun setSecure(secure: Boolean) {
        val act = activity ?: return
        act.runOnUiThread {
            val flags = WindowManager.LayoutParams.FLAG_SECURE
            if (secure) {
                act.window.setFlags(flags, flags)
            } else {
                act.window.clearFlags(flags)
            }
        }
    }

    companion object {
        const val CHANNEL = "com.tursinalabs.kelola/app_lock"
    }
}
