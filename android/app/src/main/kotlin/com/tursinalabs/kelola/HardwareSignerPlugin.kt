package com.tursinalabs.kelola

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.security.keystore.UserNotAuthenticatedException
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.cert.Certificate
import java.security.spec.ECGenParameterSpec

class HardwareSignerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: FragmentActivity? = null

    // The result waiting on the prompt on screen, null when none is. androidx
    // keeps one client callback per activity, so a second BiometricPrompt would
    // take the touch given for the first.
    private var promptResult: MethodChannel.Result? = null

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
        // The prompt went with the activity, so no callback will end it.
        val waiting = promptResult
        promptResult = null
        waiting?.error("auth_failed", "the activity closed during the prompt", null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "generateKey" -> {
                val alias = call.argument<String>("alias") ?: run {
                    result.error("bad_args", "alias required", null)
                    return
                }
                try {
                    result.success(generateKey(alias))
                } catch (e: Exception) {
                    result.error("generate_failed", e.message, null)
                }
            }
            "sign" -> {
                val alias = call.argument<String>("alias") ?: run {
                    result.error("bad_args", "alias required", null)
                    return
                }
                val data = call.argument<ByteArray>("data") ?: run {
                    result.error("bad_args", "data required", null)
                    return
                }
                sign(alias, data, result)
            }
            "confirmPresence" -> {
                val reason = call.argument<String>("reason")
                    ?: "Confirm destructive action"
                confirmPresence(reason, result)
            }
            "keyExists" -> {
                val alias = call.argument<String>("alias") ?: run {
                    result.error("bad_args", "alias required", null)
                    return
                }
                result.success(keyStore().containsAlias(alias))
            }
            "deleteKey" -> {
                val alias = call.argument<String>("alias") ?: run {
                    result.error("bad_args", "alias required", null)
                    return
                }
                keyStore().deleteEntry(alias)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun generateKey(alias: String): Map<String, Any> {
        val ks = keyStore()
        if (ks.containsAlias(alias)) {
            return requireAuthBacked(alias, ks, publicPayload(alias, ks))
        }

        var backend = "software"
        val attempts = listOf(
            KeyAttempt(strongBox = true, label = "strongbox"),
            KeyAttempt(strongBox = false, label = "tee"),
        )
        var last: Exception? = null
        for (attempt in attempts) {
            try {
                createKey(alias, attempt)
                backend = attempt.label
                last = null
                break
            } catch (e: Exception) {
                last = e
                Log.w(TAG, "key gen ${attempt.label} failed: ${e.message}")
            }
        }
        if (last != null && !ks.containsAlias(alias)) {
            throw last
        }
        val payload = publicPayload(alias, ks).toMutableMap()
        payload["backend"] = backend
        return requireAuthBacked(alias, ks, payload)
    }

    private fun requireAuthBacked(
        alias: String,
        ks: KeyStore,
        payload: Map<String, Any>,
    ): Map<String, Any> {
        if (payload["authRequired"] != true) {
            ks.deleteEntry(alias)
            throw IllegalStateException("refusing unauthenticated key")
        }
        return payload
    }

    private fun createKey(alias: String, attempt: KeyAttempt) {
        val purposes = KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        val builder = KeyGenParameterSpec.Builder(alias, purposes)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 300s read/mutate window (Fleet one-auth). Destructive actions
            // use an app-level BiometricPrompt gate — Keystore cannot re-auth
            // selected ops on a timed key without a second alias.
            builder.setUserAuthenticationParameters(
                300,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        }
        if (attempt.strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                builder.setIsStrongBoxBacked(true)
            } catch (_: StrongBoxUnavailableException) {
                throw IllegalStateException("StrongBox unavailable")
            }
        }
        val gen = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE)
        gen.initialize(builder.build())
        gen.generateKeyPair()
        val created = keyStore()
        val privateKey = created.getKey(alias, null) as? PrivateKey
            ?: throw IllegalStateException("key missing after generate")
        val factory = KeyFactory.getInstance(privateKey.algorithm, ANDROID_KEYSTORE)
        val info = factory.getKeySpec(privateKey, KeyInfo::class.java)
        if (!info.isUserAuthenticationRequired) {
            created.deleteEntry(alias)
            throw IllegalStateException("refusing unauthenticated key")
        }
    }

    private fun publicPayload(alias: String, ks: KeyStore): Map<String, Any> {
        val cert: Certificate = ks.getCertificate(alias)
            ?: throw IllegalStateException("no public cert for $alias")
        var backend = "tee"
        var auth = false
        try {
            val privateKey = ks.getKey(alias, null) as? PrivateKey
            if (privateKey != null) {
                val factory = KeyFactory.getInstance(privateKey.algorithm, ANDROID_KEYSTORE)
                val info = factory.getKeySpec(privateKey, KeyInfo::class.java)
                auth = info.isUserAuthenticationRequired
                backend = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    when (info.securityLevel) {
                        KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                        KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                        else -> "software"
                    }
                } else if (info.isInsideSecureHardware) {
                    "tee"
                } else {
                    "software"
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "key info: ${e.message}")
        }
        return mapOf(
            "publicKeySpki" to cert.publicKey.encoded,
            "backend" to backend,
            "authRequired" to auth,
        )
    }

    // BiometricPrompt returns without any callback once state is saved, so a
    // prompt is only started when it will show. Every start needs an endPrompt.
    private fun beginPrompt(act: FragmentActivity, result: MethodChannel.Result): Boolean {
        if (act.supportFragmentManager.isStateSaved) {
            result.error("auth_failed", "the app is not in the foreground", null)
            return false
        }
        promptResult = result
        return true
    }

    // False once the prompt has already been ended and its result answered.
    private fun endPrompt(result: MethodChannel.Result): Boolean {
        if (promptResult !== result) {
            return false
        }
        promptResult = null
        return true
    }

    private fun confirmPresence(reason: String, result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("no_activity", "confirmPresence requires an activity", null)
            return
        }
        if (promptResult != null) {
            result.error("busy", "another prompt is open", null)
            return
        }
        if (!beginPrompt(act, result)) {
            return
        }
        val prompt = BiometricPrompt(
            act,
            ContextCompat.getMainExecutor(act),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResult: BiometricPrompt.AuthenticationResult,
                ) {
                    if (endPrompt(result)) {
                        result.success(null)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (endPrompt(result)) {
                        result.error("auth_failed", errString.toString(), null)
                    }
                }
            },
        )
        try {
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(reason)
                    .setSubtitle("Confirm it's you")
                    .setNegativeButtonText("Cancel")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    .build(),
            )
        } catch (e: Exception) {
            if (endPrompt(result)) {
                result.error("auth_failed", e.message, null)
            }
        }
    }

    private fun sign(alias: String, data: ByteArray, result: MethodChannel.Result) {
        val ks = keyStore()
        val privateKey = ks.getKey(alias, null) as? PrivateKey
            ?: run {
                result.error("missing_key", "no private key $alias", null)
                return
            }
        val act = activity
        if (act == null) {
            result.error("no_activity", "signing requires an activity", null)
            return
        }
        try {
            result.success(signWith(privateKey, data))
        } catch (_: UserNotAuthenticatedException) {
            // Timed-auth keys (300s window): unlock with a plain BiometricPrompt.
            // CryptoObject + initSign throws UserNotAuthenticatedException while
            // the window is closed — the prompt never appears.
            unlockThenSign(act, privateKey, data, result)
        } catch (e: Exception) {
            // Per-use keys (timeout 0): must bind Signature via CryptoObject.
            signWithCryptoObject(act, privateKey, data, result, e)
        }
    }

    private fun signWith(privateKey: PrivateKey, data: ByteArray): ByteArray {
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(privateKey)
        signature.update(data)
        return signature.sign()
    }

    private fun unlockThenSign(
        act: FragmentActivity,
        privateKey: PrivateKey,
        data: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (!beginPrompt(act, result)) {
            return
        }
        val prompt = BiometricPrompt(
            act,
            ContextCompat.getMainExecutor(act),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResult: BiometricPrompt.AuthenticationResult,
                ) {
                    if (!endPrompt(result)) {
                        return
                    }
                    try {
                        result.success(signWith(privateKey, data))
                    } catch (e: Exception) {
                        result.error("sign_failed", e.message, null)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (endPrompt(result)) {
                        result.error("auth_failed", errString.toString(), null)
                    }
                }
            },
        )
        try {
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle("Sign SSH challenge")
                    .setSubtitle("The private key never leaves this device")
                    .setNegativeButtonText("Cancel")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    .build(),
            )
        } catch (e: Exception) {
            if (endPrompt(result)) {
                result.error("sign_failed", e.message, null)
            }
        }
    }

    private fun signWithCryptoObject(
        act: FragmentActivity,
        privateKey: PrivateKey,
        data: ByteArray,
        result: MethodChannel.Result,
        firstError: Exception,
    ) {
        // Before the prompt is built: building one replaces the live callback.
        val cryptoSig = try {
            Signature.getInstance("SHA256withECDSA").apply { initSign(privateKey) }
        } catch (e: UserNotAuthenticatedException) {
            unlockThenSign(act, privateKey, data, result)
            return
        } catch (e: Exception) {
            result.error("sign_failed", e.message ?: firstError.message, null)
            return
        }
        if (!beginPrompt(act, result)) {
            return
        }
        val prompt = BiometricPrompt(
            act,
            ContextCompat.getMainExecutor(act),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResult: BiometricPrompt.AuthenticationResult,
                ) {
                    if (!endPrompt(result)) {
                        return
                    }
                    try {
                        val crypto = authResult.cryptoObject?.signature
                            ?: throw IllegalStateException(
                                firstError.message ?: "crypto object missing",
                            )
                        crypto.update(data)
                        result.success(crypto.sign())
                    } catch (e: Exception) {
                        result.error("sign_failed", e.message, null)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (endPrompt(result)) {
                        result.error("auth_failed", errString.toString(), null)
                    }
                }
            },
        )
        try {
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle("Sign SSH challenge")
                    .setSubtitle("The private key never leaves this device")
                    .setNegativeButtonText("Cancel")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    .build(),
                BiometricPrompt.CryptoObject(cryptoSig),
            )
        } catch (e: Exception) {
            if (endPrompt(result)) {
                result.error("sign_failed", e.message ?: firstError.message, null)
            }
        }
    }

    private fun keyStore(): KeyStore {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
        ks.load(null)
        return ks
    }

    private data class KeyAttempt(
        val strongBox: Boolean,
        val label: String,
    )

    companion object {
        private const val CHANNEL = "com.tursinalabs.kelola/hardware_signer"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TAG = "KelolaSigner"
    }
}
