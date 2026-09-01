package labs.tursina.kelola

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
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
import android.security.keystore.KeyInfo
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
            return publicPayload(alias, ks)
        }

        var backend = "software"
        var auth = false
        val attempts = listOf(
            KeyAttempt(strongBox = true, auth = true, label = "strongbox"),
            KeyAttempt(strongBox = false, auth = true, label = "tee"),
            KeyAttempt(strongBox = false, auth = false, label = "tee"),
        )
        var last: Exception? = null
        for (attempt in attempts) {
            try {
                createKey(alias, attempt)
                backend = attempt.label
                auth = attempt.auth
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
        payload["authRequired"] = auth
        return payload
    }

    private fun createKey(alias: String, attempt: KeyAttempt) {
        val purposes = KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        val builder = KeyGenParameterSpec.Builder(alias, purposes)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(attempt.auth)
        if (attempt.auth && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
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

    private fun sign(alias: String, data: ByteArray, result: MethodChannel.Result) {
        val ks = keyStore()
        val privateKey = ks.getKey(alias, null) as? PrivateKey
            ?: run {
                result.error("missing_key", "no private key $alias", null)
                return
            }
        val signature = Signature.getInstance("SHA256withECDSA")
        val act = activity
        if (act == null) {
            result.error("no_activity", "signing requires an activity", null)
            return
        }
        try {
            signature.initSign(privateKey)
            signature.update(data)
            result.success(signature.sign())
        } catch (_: Exception) {
            val prompt = BiometricPrompt(
                act,
                ContextCompat.getMainExecutor(act),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authResult: BiometricPrompt.AuthenticationResult,
                    ) {
                        try {
                            val crypto = authResult.cryptoObject?.signature
                                ?: signature
                            crypto.update(data)
                            result.success(crypto.sign())
                        } catch (e: Exception) {
                            result.error("sign_failed", e.message, null)
                        }
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        result.error("auth_failed", errString.toString(), null)
                    }
                },
            )
            try {
                val cryptoSig = Signature.getInstance("SHA256withECDSA")
                cryptoSig.initSign(privateKey)
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
                result.error("sign_failed", e.message, null)
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
        val auth: Boolean,
        val label: String,
    )

    companion object {
        private const val CHANNEL = "labs.tursina.kelola/hardware_signer"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TAG = "KelolaSigner"
    }
}
