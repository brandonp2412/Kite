package app.kite

import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodChannel

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.SurfaceView
import android.view.TextureView

import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentActivity = this
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= 35) {
            val flutterView = findFlutterView(window.decorView)
            val renderView = flutterView?.let { findRenderView(it) }
            renderView?.setRequestedFrameRate(View.REQUESTED_FRAME_RATE_CATEGORY_DEFAULT)
        }
        if (currentActivity === this) currentActivity = null
        super.onDestroy()
    }

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(context.applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    // Keep the shared engine alive when the activity is closed so push handling
    // can reuse the same isolate instead of starting a second Flutter engine.
    override fun createFlutterFragment(): FlutterFragment =
        super.createFlutterFragment().apply {
            arguments?.putBoolean("destroy_engine_with_fragment", false)
        }

    companion object {
        private const val FCM_CHANNEL = "app.kite/fcm"
        private const val CHAT_SCROLL_CHANNEL = "app.kite/chat_scroll"
        private var fcmChannelEngine: FlutterEngine? = null
        private var chatScrollChannelEngine: FlutterEngine? = null
        private var currentActivity: MainActivity? = null

        var engine: FlutterEngine? = null

        fun provideEngine(context: Context): FlutterEngine {
            engine?.let {
                configureFcmChannel(it)
                return it
            }

            val eng = FlutterEngine(context.applicationContext, emptyArray(), true, false)
            eng.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() = Unit

                override fun onEngineWillDestroy() {
                    if (engine === eng) {
                        engine = null
                    }
                    if (fcmChannelEngine === eng) {
                        fcmChannelEngine = null
                    }
                }
            })

            engine = eng
            configureFcmChannel(eng)
            return eng
        }

        fun provideRunningEngine(context: Context): FlutterEngine {
            var eng = engine
            if (eng == null) {
                eng = provideEngine(context.applicationContext)
                eng.localizationPlugin.sendLocalesToFlutter(
                    context.resources.configuration,
                )
                eng.dartExecutor.executeDartEntrypoint(
                    DartEntrypoint.createDefault(),
                )
            }
            return eng
        }

        private fun configureFcmChannel(engine: FlutterEngine) {
            configureChatScrollChannel(engine)
            if (fcmChannelEngine === engine) return

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

            fcmChannelEngine = engine
        }

        private fun configureChatScrollChannel(engine: FlutterEngine) {
            if (chatScrollChannelEngine === engine) return

            MethodChannel(engine.dartExecutor.binaryMessenger, CHAT_SCROLL_CHANNEL)
                .setMethodCallHandler { call, result ->
                    val scrolling = call.method == "scrolling"
                    if (call.method != "scrolling" && call.method != "idle") {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    val activity = currentActivity
                    if (activity == null || Build.VERSION.SDK_INT < 35) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    activity.runOnUiThread {
                        val flutterView = activity.findFlutterView(activity.window.decorView)
                        val renderView = flutterView?.let { activity.findRenderView(it) } ?: flutterView
                        renderView?.setRequestedFrameRate(
                            if (scrolling) activity.display?.refreshRate ?: 60f
                            else View.REQUESTED_FRAME_RATE_CATEGORY_DEFAULT,
                        )
                        result.success(null)
                    }
                }

            chatScrollChannelEngine = engine
        }

        private fun MainActivity.findFlutterView(root: View): View? {
            if (root.javaClass.name == "io.flutter.embedding.android.FlutterView") {
                return root
            }
            if (root is ViewGroup) {
                for (index in 0 until root.childCount) {
                    findFlutterView(root.getChildAt(index))?.let { return it }
                }
            }
            return null
        }

        private fun MainActivity.findRenderView(root: View): View? {
            if (root is SurfaceView || root is TextureView) return root
            if (root is ViewGroup) {
                for (index in 0 until root.childCount) {
                    findRenderView(root.getChildAt(index))?.let { return it }
                }
            }
            return null
        }
    }
}
