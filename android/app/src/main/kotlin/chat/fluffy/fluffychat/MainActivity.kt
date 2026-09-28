package chat.fluffy.fluffychat

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.content.Context

import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    companion object {
        private const val FCM_CHANNEL = "chat.fluffy.fluffychat.test/fcm"
        private var fcmChannelConfigured = false

        var engine: FlutterEngine? = null

        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            configureFcmChannel(eng)
            return eng
        }

        private fun configureFcmChannel(engine: FlutterEngine) {
            if (fcmChannelConfigured) return

            MethodChannel(engine.dartExecutor.binaryMessenger, FCM_CHANNEL)
                .setMethodCallHandler { call, result ->
                    if (call.method != "registerInstallation") {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }

                    FirebaseMessaging.getInstance().register()
                        .addOnCompleteListener { registration ->
                            if (!registration.isSuccessful) {
                                result.error(
                                    "FCM_REGISTER_FAILED",
                                    registration.exception?.message ?: "FCM registration failed",
                                    null,
                                )
                                return@addOnCompleteListener
                            }

                            FirebaseInstallations.getInstance().id
                                .addOnSuccessListener { installationId ->
                                    result.success(installationId)
                                }
                                .addOnFailureListener { error ->
                                    result.error(
                                        "FID_FAILED",
                                        error.message ?: "Unable to get Firebase Installation ID",
                                        null,
                                    )
                                }
                        }
                }

            fcmChannelConfigured = true
        }
    }
}
