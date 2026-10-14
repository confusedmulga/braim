package com.solo.braim

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A small translucent activity for ACTION_SEND text shares. It runs the
// `shareMain` Dart entrypoint, which renders just a folder-picker popup over
// the sharing app (Pinterest-style) instead of opening the full app.
class ShareActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "shareMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        // A shared text *file* (a .txt, or a .md sent as text/plain) carries
        // no link to file away: the main app saves it as a note, as it does a
        // .md shared under its own type.
        val shared = intent
        val isFile = savedInstanceState == null &&
            shared?.action == Intent.ACTION_SEND &&
            shared.getStringExtra(Intent.EXTRA_TEXT) == null &&
            shared.hasExtra(Intent.EXTRA_STREAM)
        if (isFile) {
            startActivity(
                Intent(shared).setClass(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            )
        }
        super.onCreate(savedInstanceState)
        if (isFile) finish()
    }

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
