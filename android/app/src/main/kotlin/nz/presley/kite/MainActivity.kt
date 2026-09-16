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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MATRIX_BOOTSTRAP_CHANNEL,
        ).setMethodCallHandler(::handleMatrixBootstrapCall)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LOCK_CHANNEL,
        ).setMethodCallHandler(null)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MATRIX_BOOTSTRAP_CHANNEL,
        ).setMethodCallHandler(null)
        appLockExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleMatrixBootstrapCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "dataRoot" -> result.success(filesDir.resolve("matrix").absolutePath)
            "resolveStoreSecret" -> onBackground(result) {
                val keyId = call.argument<String>("keyId")?.trim()
                    ?: throw IllegalArgumentException("Missing Matrix store key id.")
                require(keyId.isNotEmpty() && !keyId.contains('\u0000')) {
                    "Invalid Matrix store key id."
                }
                Base64.encodeToString(
                    hmac(keyId, MATRIX_STORE_HMAC_KEY_ALIAS),
                    Base64.NO_WRAP,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun handleAppLockCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadSettings" -> onBackground(result) { loadSettings() }
            "enablePin" -> onBackground(result) {
                val pin = requiredPin(call)
                val settings = requiredSettings(call)
                require(settings.enabled) { "App lock must be enabled when enrolling a PIN." }
                check(!preferences().contains(PIN_VERIFIER_KEY)) {
                    "App lock PIN is already enrolled."
                }
                persistEnabledSettingsWithPin(pin, settings)
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
                require(settings.enabled) {
                    "Protected app lock settings cannot disable app lock."
                }
                if (!preferences().contains(PIN_VERIFIER_KEY)) {
                    error("Cannot update app lock without an enrolled PIN.")
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
        val biometricsEnabled = preferences.getBoolean(BIOMETRICS_KEY, false)
        val hideNotificationContents = preferences.getBoolean(
            HIDE_NOTIFICATIONS_KEY,
            false,
        )
        if (enabled && !preferences.contains(PIN_VERIFIER_KEY)) {
            error("App lock credential state is incomplete.")
        }
        if (!enabled && (biometricsEnabled || hideNotificationContents)) {
            error("App lock settings are inconsistent.")
        }
        return mapOf(
            "enabled" to enabled,
            "biometricsEnabled" to biometricsEnabled,
            "hideNotificationContents" to hideNotificationContents,
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
        require(PIN_PATTERN.matches(pin)) { "PIN must contain 4 to 64 digits." }
        return pin
    }

    private fun persistSettings(settings: AppLockSettings) {
        require(
            settings.enabled ||
                (!settings.biometricsEnabled && !settings.hideNotificationContents),
        ) { "Disabled app lock cannot retain protected settings." }
        val committed = preferences().edit()
            .putBoolean(ENABLED_KEY, settings.enabled)
            .putBoolean(BIOMETRICS_KEY, settings.biometricsEnabled)
            .putBoolean(HIDE_NOTIFICATIONS_KEY, settings.hideNotificationContents)
            .commit()
        check(committed) { "App lock settings could not be persisted." }
    }

    private fun persistEnabledSettingsWithPin(pin: String, settings: AppLockSettings) {
        val verifier = Base64.encodeToString(hmac(pin), Base64.NO_WRAP)
        val committed = preferences().edit()
            .putBoolean(ENABLED_KEY, settings.enabled)
            .putBoolean(BIOMETRICS_KEY, settings.biometricsEnabled)
            .putBoolean(HIDE_NOTIFICATIONS_KEY, settings.hideNotificationContents)
            .putString(PIN_VERIFIER_KEY, verifier)
            .commit()
        check(committed) { "App lock credential state could not be persisted." }
    }

    private fun verifyPin(pin: String): Boolean {
        val encodedVerifier = preferences().getString(PIN_VERIFIER_KEY, null) ?: return false
        val expected = Base64.decode(encodedVerifier, Base64.NO_WRAP)
        val actual = hmac(pin)
        return MessageDigest.isEqual(expected, actual)
    }

    private fun hmac(pin: String): ByteArray = hmac(pin, HMAC_KEY_ALIAS)

    private fun hmac(value: String, keyAlias: String): ByteArray {
        val mac = Mac.getInstance(HMAC_ALGORITHM)
        mac.init(loadOrCreateHmacKey(keyAlias))
        return mac.doFinal(value.toByteArray(Charsets.UTF_8))
    }

    private fun loadOrCreateHmacKey(keyAlias: String = HMAC_KEY_ALIAS): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null) as? SecretKey
        if (existing != null) return existing

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_HMAC_SHA256,
            ANDROID_KEY_STORE,
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val manager = getSystemService(BiometricManager::class.java)
            return manager?.canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG,
            ) == BiometricManager.BIOMETRIC_SUCCESS
        }
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

        val promptBuilder = BiometricPrompt.Builder(this)
            .setTitle("Unlock Kite")
            .setSubtitle("Confirm your identity to continue")
            .setNegativeButton("Use PIN", mainExecutor) { _, _ -> complete(false) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            promptBuilder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG,
            )
        }
        val prompt = promptBuilder.build()
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
        const val MATRIX_BOOTSTRAP_CHANNEL = "nz.presley.kite/matrix_bootstrap"
        const val PREFERENCES_NAME = "kite_app_lock"
        const val ENABLED_KEY = "enabled"
        const val BIOMETRICS_KEY = "biometrics_enabled"
        const val HIDE_NOTIFICATIONS_KEY = "hide_notification_contents"
        const val PIN_VERIFIER_KEY = "pin_verifier"
        const val ANDROID_KEY_STORE = "AndroidKeyStore"
        const val HMAC_KEY_ALIAS = "kite_app_lock_hmac_v1"
        const val MATRIX_STORE_HMAC_KEY_ALIAS = "kite_matrix_store_hmac_v1"
        const val HMAC_ALGORITHM = "HmacSHA256"
        val PIN_PATTERN = Regex("^[0-9]{4,64}$")
    }
}
