package com.solo.braim

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth for the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    private val dndChannel = "braim/dnd"
    private val mediaChannel = "braim/media"
    private var focusMedia: FocusMedia? = null

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
