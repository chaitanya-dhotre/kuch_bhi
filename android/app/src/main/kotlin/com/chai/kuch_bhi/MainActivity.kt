package com.chai.kuch_bhi

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Recovery key copy: Flutter's Clipboard can't mark a clip sensitive,
        // and keyboards (Gboard, Samsung) keep unmarked clips in their history.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kuch_bhi/clipboard")
            .setMethodCallHandler { call, result ->
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                when (call.method) {
                    "copySensitive" -> {
                        val clip = ClipData.newPlainText("Recovery key", call.argument<String>("text"))
                        if (Build.VERSION.SDK_INT >= 24) {
                            clip.description.extras = PersistableBundle().apply {
                                // EXTRA_IS_SENSITIVE (API 33); keyboards read the same key on older Android.
                                putBoolean(
                                    if (Build.VERSION.SDK_INT >= 33) ClipDescription.EXTRA_IS_SENSITIVE
                                    else "android.content.extra.IS_SENSITIVE",
                                    true,
                                )
                            }
                        }
                        cm.setPrimaryClip(clip)
                        result.success(null)
                    }
                    "clear" -> {
                        if (Build.VERSION.SDK_INT >= 28) cm.clearPrimaryClip()
                        else cm.setPrimaryClip(ClipData.newPlainText("", ""))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
