package nz.presley.kite

import android.Manifest
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
    private val mediaSaveExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var notificationPermissionResult: MethodChannel.Result? = null

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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_CHANNEL,
        ).setMethodCallHandler(::handleNotificationCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SAVE_CHANNEL,
        ).setMethodCallHandler(::handleMediaSaveCall)
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_CHANNEL,
        ).setMethodCallHandler(null)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SAVE_CHANNEL,
        ).setMethodCallHandler(null)
        notificationPermissionResult?.error(
            "notification_permission_cancelled",
            "Notification permission request was interrupted.",
            null,
        )
        notificationPermissionResult = null
        appLockExecutor.shutdown()
        mediaSaveExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) return
        val pending = notificationPermissionResult ?: return
        notificationPermissionResult = null
        pending.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    private fun handleMediaSaveCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "media_save_unsupported",
                "Saving Matrix media to public Downloads requires Android 10 or newer.",
                null,
            )
            return
        }
        val name = call.argument<String>("name")?.trim()
        val mimeType = call.argument<String>("mimeType")?.trim()
        val bytes = call.argument<ByteArray>("bytes")
        if (
            name.isNullOrEmpty() ||
            name.contains('/') ||
            name.contains('\\') ||
            name.contains('\u0000') ||
            bytes == null ||
            bytes.isEmpty()
        ) {
            result.error("invalid_media_save", "The media save payload is invalid.", null)
            return
        }
        val resolvedMimeType = mimeType
            ?.takeIf { it.isNotEmpty() && !it.contains('\u0000') }
            ?: "application/octet-stream"
        mediaSaveExecutor.execute {
            try {
                val uri = saveMediaToDownloads(name, resolvedMimeType, bytes)
                runOnUiThread { result.success(uri) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "media_save_failed",
                        error.message ?: "Could not save Matrix media.",
                        null,
                    )
                }
            }
        }
    }

    private fun saveMediaToDownloads(
        name: String,
        mimeType: String,
        bytes: ByteArray,
    ): String {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS + "/Kite",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create a Downloads entry.")
        try {
            contentResolver.openOutputStream(uri, "w")?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("Could not open the Downloads entry.")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        } catch (error: Throwable) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private fun handleNotificationCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "show" -> {
                    showNotification(call)
                    result.success(null)
                }
                "cancel" -> {
                    val routingId = requiredNotificationString(call, "routingId")
                    notificationManager().cancel(stableNotificationId(routingId))
                    result.success(null)
                }
                "showSummary" -> {
                    showNotificationSummary(call)
                    result.success(null)
                }
                "cancelSummary" -> {
                    val groupKey = requiredNotificationString(call, "groupKey")
                    notificationManager().cancel(stableNotificationId("summary:" + groupKey))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error(
                "notification_operation_failed",
                error.message ?: "Notification operation failed.",
                null,
            )
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        ensureNotificationChannel()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error(
                "notification_permission_pending",
                "A notification permission request is already pending.",
                null,
            )
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun showNotification(call: MethodCall) {
        requireNotificationsAllowed()
        ensureNotificationChannel()

        val routingId = requiredNotificationString(call, "routingId")
        val groupKey = requiredNotificationString(call, "groupKey")
        val title = requiredNotificationString(call, "title")
        val body = requiredNotificationString(call, "body")
        val intent = notificationIntent(call, routingId)
        val notification = notificationBuilder()
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setGroup(groupKey)
            .setContentIntent(intent)
            .build()

        notificationManager().notify(stableNotificationId(routingId), notification)
    }

    private fun showNotificationSummary(call: MethodCall) {
        requireNotificationsAllowed()
        ensureNotificationChannel()

        val groupKey = requiredNotificationString(call, "groupKey")
        val count = call.argument<Int>("count")
            ?: throw IllegalArgumentException("Missing notification summary count.")
        require(count > 1) { "Notification summary count must be greater than one." }
        val body = count.toString() + " new notifications"
        val notification = notificationBuilder()
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Kite")
            .setContentText(body)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setGroup(groupKey)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .build()
        notificationManager().notify(
            stableNotificationId("summary:" + groupKey),
            notification,
        )
    }

    private fun notificationIntent(
        call: MethodCall,
        routingId: String,
    ): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = NOTIFICATION_OPEN_ACTION
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("routingId", routingId)
            putExtra("accountId", requiredNotificationString(call, "accountId"))
            putExtra("roomId", requiredNotificationString(call, "roomId"))
            optionalNotificationString(call, "eventId")?.let { putExtra("eventId", it) }
            optionalNotificationString(call, "threadRootEventId")
                ?.let { putExtra("threadRootEventId", it) }
            optionalNotificationString(call, "callId")?.let { putExtra("callId", it) }
        }
        return PendingIntent.getActivity(
            this,
            stableNotificationId(routingId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationBuilder(): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        notificationManager().createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Messages",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Matrix messages and invitations"
            },
        )
    }

    private fun requireNotificationsAllowed() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw IllegalStateException("Notification permission has not been granted.")
        }
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun requiredNotificationString(call: MethodCall, name: String): String {
        val value = call.argument<String>(name)
            ?: throw IllegalArgumentException("Missing notification field: " + name)
        require(value.isNotEmpty() && value == value.trim() && !value.contains('\u0000')) {
            "Invalid notification field: " + name
        }
        return value
    }

    private fun optionalNotificationString(call: MethodCall, name: String): String? {
        val value = call.argument<String>(name) ?: return null
        require(value.isNotEmpty() && value == value.trim() && !value.contains('\u0000')) {
            "Invalid notification field: " + name
        }
        return value
    }

    private fun stableNotificationId(value: String): Int {
        val id = value.hashCode() and Int.MAX_VALUE
        return if (id == 0) 1 else id
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
        const val NOTIFICATION_CHANNEL = "nz.presley.kite/notifications"
        const val MEDIA_SAVE_CHANNEL = "nz.presley.kite/media_save"
        const val NOTIFICATION_CHANNEL_ID = "kite_messages"
        const val NOTIFICATION_OPEN_ACTION = "nz.presley.kite.OPEN_NOTIFICATION"
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4601
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
