package com.keepy.keepy

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A small translucent activity for ACTION_SEND text shares. It runs the
// `shareMain` Dart entrypoint, which renders just a folder-picker popup over
// the sharing app (Pinterest-style) instead of opening the full app.
class ShareActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "shareMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "braim/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedText" -> {
                        val text = if (intent?.action == Intent.ACTION_SEND)
                            intent.getStringExtra(Intent.EXTRA_TEXT) else null
                        result.success(text)
                    }
                    "close" -> {
                        result.success(null)
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
