package com.solo.braim

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth for the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    private val dndChannel = "braim/dnd"
    private val mediaChannel = "braim/media"
    private val webBundleChannel = "braim/webbundle"
    private var focusMedia: FocusMedia? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Draw behind the status and navigation bars from the first frame on
        // every Android version; Android 15+ enforces this anyway. Called after
        // super.onCreate so it wins over the translucent status bar Flutter's
        // activity sets while starting up. Both bars stay transparent, and an
        // explicit light/dark style (not auto) keeps the navigation-bar contrast
        // scrim off, so no white band paints behind the gesture pill. Dart then
        // takes over the bar icons per screen (main.dart, AnnotatedRegion).
        val night = (resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val bars = if (night) {
            SystemBarStyle.dark(Color.TRANSPARENT)
        } else {
            SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
        }
        enableEdgeToEdge(statusBarStyle = bars, navigationBarStyle = bars)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pomodoro media notification (MediaSession-backed).
        val media = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
        val fm = FocusMedia(applicationContext)
        fm.onAction = { action -> runOnUiThread { media.invokeMethod("mediaAction", action) } }
        focusMedia = fm
        media.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    fm.show(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                        (call.argument<Number>("elapsedMs") ?: 0).toLong(),
                        (call.argument<Number>("durationMs") ?: 0).toLong(),
                        call.argument<Boolean>("playing") ?: false,
                        (call.argument<Number>("color") ?: 0).toInt(),
                    )
                    result.success(true)
                }
                "hide" -> {
                    fm.hide()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // "Open on computer": the web app's files ship in the APK's native
        // assets (assets/web/, written by tool/build_web_bundle.sh) and are
        // served to the browser by the Dart phone server.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, webBundleChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> {
                        val path = call.argument<String>("path") ?: ""
                        if (path.isEmpty() || path.contains("..")) {
                            result.success(null)
                        } else {
                            Thread {
                                val bytes = try {
                                    assets.open("web/$path").use { it.readBytes() }
                                } catch (e: Exception) {
                                    null
                                }
                                runOnUiThread { result.success(bytes) }
                            }.start()
                        }
                    }
                    // Keep the phone awake while a computer is using it, so the
                    // server doesn't sleep with the screen.
                    "keepAwake" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, dndChannel)
            .setMethodCallHandler { call, result ->
                // Do Not Disturb needs API 23+. On older devices every call
                // reports "unsupported" so the focus timer degrades gracefully.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    when (call.method) {
                        "hasAccess" -> result.success(false)
                        "getFilter" -> result.success(-1)
                        "setFilter", "openSettings" -> result.success(false)
                        else -> result.notImplemented()
                    }
                    return@setMethodCallHandler
                }
                val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                when (call.method) {
                    "hasAccess" ->
                        result.success(nm.isNotificationPolicyAccessGranted)
                    "openSettings" -> {
                        val intent =
                            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    "getFilter" -> result.success(
                        if (nm.isNotificationPolicyAccessGranted)
                            nm.currentInterruptionFilter else -1
                    )
                    "setFilter" -> {
                        val filter = call.argument<Int>("filter") ?: 1
                        if (nm.isNotificationPolicyAccessGranted) {
                            nm.setInterruptionFilter(filter)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
