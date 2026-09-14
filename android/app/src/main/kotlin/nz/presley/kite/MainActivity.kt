package nz.presley.kite

import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

class MainActivity : FlutterActivity() {
    private val appLockExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LOCK_CHANNEL,
        ).setMethodCallHandler(::handleAppLockCall)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LOCK_CHANNEL,
        ).setMethodCallHandler(null)
        appLockExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleAppLockCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadSettings" -> onBackground(result) { loadSettings() }
            "enablePin" -> onBackground(result) {
                val pin = requiredPin(call)
                val settings = requiredSettings(call)
                require(settings.enabled) { "App lock must be enabled when enrolling a PIN." }
                savePinVerifier(pin)
                persistSettings(settings)
                null
            }
            "verifyPin" -> onBackground(result) {
                verifyPin(requiredPin(call))
            }
            "disable" -> onBackground(result) {
                disableAppLock()
                null
            }
            "saveSettings" -> onBackground(result) {
                val settings = requiredSettings(call)
                if (settings.enabled && !preferences().contains(PIN_VERIFIER_KEY)) {
                    error("Cannot enable app lock without an enrolled PIN.")
                }
                persistSettings(settings)
                null
            }
            "isBiometricAvailable" -> result.success(isBiometricAvailable())
            "authenticateBiometric" -> authenticateBiometric(result)
            else -> result.notImplemented()
        }
    }

    private fun onBackground(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        appLockExecutor.execute {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "app_lock_operation_failed",
                        error.message ?: "App lock operation failed.",
                        null,
                    )
                }
            }
        }
    }

    private fun loadSettings(): Map<String, Any> {
        val preferences = preferences()
        val enabled = preferences.getBoolean(ENABLED_KEY, false)
        if (enabled && !preferences.contains(PIN_VERIFIER_KEY)) {
            error("App lock credential state is incomplete.")
        }
        return mapOf(
            "enabled" to enabled,
            "biometricsEnabled" to preferences.getBoolean(BIOMETRICS_KEY, false),
            "hideNotificationContents" to preferences.getBoolean(
                HIDE_NOTIFICATIONS_KEY,
                false,
            ),
        )
    }

    private fun requiredSettings(call: MethodCall): AppLockSettings {
        return AppLockSettings(
            enabled = requiredBoolean(call, "enabled"),
            biometricsEnabled = requiredBoolean(call, "biometricsEnabled"),
            hideNotificationContents = requiredBoolean(call, "hideNotificationContents"),
        )
    }

    private fun requiredBoolean(call: MethodCall, name: String): Boolean {
        return call.argument<Boolean>(name)
            ?: throw IllegalArgumentException("Missing app lock setting: $name")
    }

    private fun requiredPin(call: MethodCall): String {
        val pin = call.argument<String>("pin")
            ?: throw IllegalArgumentException("Missing app lock PIN.")
        require(PIN_PATTERN.matches(pin)) { "PIN must contain at least four digits." }
        return pin
    }

    private fun persistSettings(settings: AppLockSettings) {
        val committed = preferences().edit()
            .putBoolean(ENABLED_KEY, settings.enabled)
            .putBoolean(BIOMETRICS_KEY, settings.biometricsEnabled)
            .putBoolean(HIDE_NOTIFICATIONS_KEY, settings.hideNotificationContents)
            .commit()
        check(committed) { "App lock settings could not be persisted." }
    }

    private fun savePinVerifier(pin: String) {
        val verifier = Base64.encodeToString(hmac(pin), Base64.NO_WRAP)
        val committed = preferences().edit()
            .putString(PIN_VERIFIER_KEY, verifier)
            .commit()
        check(committed) { "App lock credential could not be persisted." }
    }

    private fun verifyPin(pin: String): Boolean {
        val encodedVerifier = preferences().getString(PIN_VERIFIER_KEY, null) ?: return false
        val expected = Base64.decode(encodedVerifier, Base64.NO_WRAP)
        val actual = hmac(pin)
        return MessageDigest.isEqual(expected, actual)
    }

    private fun hmac(pin: String): ByteArray {
        val mac = Mac.getInstance(HMAC_ALGORITHM)
        mac.init(loadOrCreateHmacKey())
        return mac.doFinal(pin.toByteArray(Charsets.UTF_8))
    }

    private fun loadOrCreateHmacKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        val existing = keyStore.getKey(HMAC_KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_HMAC_SHA256,
            ANDROID_KEY_STORE,
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                HMAC_KEY_ALIAS,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            )
                .setDigests(KeyProperties.DIGEST_SHA256)
                .build(),
        )
        return keyGenerator.generateKey()
    }

    private fun disableAppLock() {
        val committed = preferences().edit()
            .remove(ENABLED_KEY)
            .remove(BIOMETRICS_KEY)
            .remove(HIDE_NOTIFICATIONS_KEY)
            .remove(PIN_VERIFIER_KEY)
            .commit()
        check(committed) { "App lock state could not be cleared." }

        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        if (keyStore.containsAlias(HMAC_KEY_ALIAS)) {
            keyStore.deleteEntry(HMAC_KEY_ALIAS)
        }
    }

    private fun isBiometricAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val manager = getSystemService(BiometricManager::class.java)
            return manager?.canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS
        }

        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT) &&
            keyguard?.isDeviceSecure == true
    }

    private fun authenticateBiometric(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || !isBiometricAvailable()) {
            result.success(false)
            return
        }

        val completed = AtomicBoolean(false)
        fun complete(value: Boolean) {
            if (completed.compareAndSet(false, true)) result.success(value)
        }

        val prompt = BiometricPrompt.Builder(this)
            .setTitle("Unlock Kite")
            .setSubtitle("Confirm your identity to continue")
            .setNegativeButton("Use PIN", mainExecutor) { _, _ -> complete(false) }
            .build()
        prompt.authenticate(
            android.os.CancellationSignal(),
            mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    complete(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    complete(false)
                }
            },
        )
    }

    private fun preferences() = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    private data class AppLockSettings(
        val enabled: Boolean,
        val biometricsEnabled: Boolean,
        val hideNotificationContents: Boolean,
    )

    private companion object {
        const val APP_LOCK_CHANNEL = "nz.presley.kite/app_lock"
        const val PREFERENCES_NAME = "kite_app_lock"
        const val ENABLED_KEY = "enabled"
        const val BIOMETRICS_KEY = "biometrics_enabled"
        const val HIDE_NOTIFICATIONS_KEY = "hide_notification_contents"
        const val PIN_VERIFIER_KEY = "pin_verifier"
        const val ANDROID_KEY_STORE = "AndroidKeyStore"
        const val HMAC_KEY_ALIAS = "kite_app_lock_hmac_v1"
        const val HMAC_ALGORITHM = "HmacSHA256"
        val PIN_PATTERN = Regex("^[0-9]{4,}$")
    }
}
