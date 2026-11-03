package com.chai.kuch_bhi

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.ContentResolver
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private var shareChannel: MethodChannel? = null

    // One thread: copies run in order and clearShared never races a copy.
    private val shareIo = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())
    private var shareFolder = 0 // touched on shareIo only

    override fun onCreate(savedInstanceState: Bundle?) {
        // Recreated after process death or a config change: the old share
        // would come back without LAUNCHED_FROM_HISTORY.
        if (savedInstanceState != null) intent = Intent(Intent.ACTION_MAIN)
        super.onCreate(savedInstanceState)
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kuch_bhi/privacy")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHideInRecents" -> {
                        val hide = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (Build.VERSION.SDK_INT >= 33) {
                                this@MainActivity.setRecentsScreenshotEnabled(!hide)
                            } else if (hide) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        }
                    }
                    "moveTaskToBack" -> runOnUiThread {
                        result.success(moveTaskToBack(true))
                    }
                    else -> result.notImplemented()
                }
            }
        // Share into the app (12.1): links + names first, a copy only after
        // a chat is picked. Never log a URI, name, size or the shared text.
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kuch_bhi/share")
            .apply { setMethodCallHandler(::onShareCall) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (!isShare(intent)) return
        setIntent(intent)
        shareChannel?.invokeMethod("shareArrived", null)
    }

    // Recents replays the original intent after a kill: never a share again.
    private fun isShare(i: Intent?): Boolean =
        i != null &&
            (i.action == Intent.ACTION_SEND || i.action == Intent.ACTION_SEND_MULTIPLE) &&
            i.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0

    private fun onShareCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeShare" -> {
                val share = intent
                if (!isShare(share)) return result.success(null)
                intent = Intent(Intent.ACTION_MAIN) // consumed once
                onShareIo(result) { describeShare(share) }
            }
            "copyShared" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name")
                val maxBytes = call.argument<Number>("maxBytes")?.toLong()
                if (uri == null || name == null || maxBytes == null) {
                    return result.error("unreadable", null, null)
                }
                onShareIo(result) { copyShared(Uri.parse(uri), name, maxBytes) }
            }
            "clearShared" -> onShareIo(result) {
                File(cacheDir, "share_in").deleteRecursively()
                null
            }
            else -> result.notImplemented()
        }
    }

    private class ShareCopyError(val code: String) : Exception(code)

    private fun onShareIo(result: MethodChannel.Result, work: () -> Any?) {
        shareIo.execute {
            val out = try {
                Result.success(work())
            } catch (e: Exception) {
                Result.failure(e)
            }
            mainThread.post {
                out.fold(
                    { result.success(it) },
                    {
                        val code = (it as? ShareCopyError)?.code ?: "unreadable"
                        Log.w(TAG, "[Share] failed: $code")
                        result.error(code, null, null)
                    },
                )
            }
        }
    }

    private fun describeShare(share: Intent): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val uris: List<Uri> = if (share.action == Intent.ACTION_SEND_MULTIPLE) {
            share.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        } else {
            listOfNotNull(share.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        }
        val items = uris.mapIndexedNotNull { n, uri -> describeItem(uri, share.type, n) }
        Log.i(TAG, "[Share] ${items.size} items: " + items.joinToString { (it["mime"] as String).substringBefore('/') })
        // EXTRA_SUBJECT is ignored on purpose (Chrome's page title).
        return mapOf("items" to items, "text" to share.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString())
    }

    // Content links only, never our own files ("Dirty Stream"); share_plus's
    // provider is ours too but holds only what we chose to share out.
    private fun allowed(uri: Uri): Boolean {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return false
        val authority = uri.authority ?: return false
        return !authority.startsWith(packageName) || authority == "$packageName.flutter.share_provider"
    }

    // Reads the provider's columns only; nothing is copied here.
    private fun describeItem(uri: Uri, intentType: String?, n: Int): Map<String, Any?>? = try {
        if (!allowed(uri)) throw SecurityException()
        var name: String? = null
        var size = -1L
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { c ->
                if (c.moveToFirst()) {
                    val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (ni >= 0 && !c.isNull(ni)) name = c.getString(ni)
                    val si = c.getColumnIndex(OpenableColumns.SIZE)
                    if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
                }
            }
        val ext = name?.substringAfterLast('.', "")?.lowercase().orEmpty()
        val mime = contentResolver.getType(uri)
            ?: intentType?.takeUnless { it == "*/*" }
            ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
        val fallbackExt = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        mapOf(
            "uri" to uri.toString(),
            "mime" to mime,
            "name" to (name ?: "shared_${n + 1}" + (fallbackExt?.let { ".$it" } ?: "")),
            "size" to size,
        )
    } catch (e: Exception) {
        null // unreadable: left out of the share
    }

    // One folder per item so two IMG_0001.jpg never overwrite each other.
    private fun copyShared(uri: Uri, name: String, maxBytes: Long): String {
        val dir = File(cacheDir, "share_in/${++shareFolder}")
        try {
            if (!allowed(uri)) throw ShareCopyError("unreadable")
            val safe = safeName(name)
            dir.mkdirs()
            val file = File(dir, safe)
            val input = contentResolver.openInputStream(uri) ?: throw IOException()
            input.use { from ->
                file.outputStream().use { to ->
                    val buf = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = from.read(buf)
                        if (read < 0) break
                        total += read
                        if (total > maxBytes) throw ShareCopyError("too_big")
                        to.write(buf, 0, read)
                    }
                }
            }
            return file.path
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw if (e is ShareCopyError) e else ShareCopyError("unreadable")
        }
    }

    // No `/`, `\` or leading dots; at most 120 characters and 200 bytes
    // (ext4 allows 255), cut on a whole character, extension kept.
    private fun safeName(name: String): String {
        val clean = name.replace("/", "").replace("\\", "").trimStart('.')
        val dot = clean.lastIndexOf('.')
        val ext = if (dot > 0 && clean.length - dot <= 10) clean.substring(dot) else ""
        var base = clean.removeSuffix(ext)
        while (base.isNotEmpty() && ((base + ext).length > 120 || (base + ext).toByteArray().size > 200)) {
            base = base.substring(0, base.offsetByCodePoints(base.length, -1))
        }
        return if (base.isEmpty()) "shared$ext" else base + ext
    }

    private companion object {
        const val TAG = "KuchBhi"
    }
}
