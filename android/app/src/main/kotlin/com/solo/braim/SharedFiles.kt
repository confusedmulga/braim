package com.solo.braim

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.File

/**
 * Files shared to Braim (or opened with it) come in as content:// links. The
 * share plugin copies each into the cache under the name the sending app
 * gives, as is, so a name like "../files/x" would land outside the cache.
 * Before the plugin sees an incoming intent, [safeCopy] copies its files
 * itself, under a cleaned name in a folder of their own, and hands the plugin
 * those local files instead: it then reads them where they are.
 */
object SharedFiles {
    private const val FOLDER = "incoming"
    private const val KEEP_MS = 24L * 60 * 60 * 1000

    /**
     * [intent] with its shared files swapped for safe local copies. One whose
     * files can't be read becomes a plain launch: the app just opens.
     */
    fun safeCopy(context: Context, intent: Intent?): Intent? {
        if (intent == null) return null
        return try {
            when (intent.action) {
                Intent.ACTION_VIEW -> {
                    val link = intent.data
                    if (link?.scheme != "content") return intent
                    val copy = copyIn(context, link) ?: return plainLaunch()
                    Intent(intent).apply {
                        setDataAndType(copy, intent.type)
                        clipData = null
                    }
                }
                Intent.ACTION_SEND -> {
                    val stream = streamOf(intent) ?: return intent
                    if (stream.scheme != "content") return intent
                    val copy = copyIn(context, stream) ?: return plainLaunch()
                    Intent(intent).apply {
                        putExtra(Intent.EXTRA_STREAM, copy)
                        clipData = null
                    }
                }
                Intent.ACTION_SEND_MULTIPLE -> {
                    val streams = streamsOf(intent) ?: return intent
                    val copies = ArrayList<Uri>()
                    for (uri in streams) {
                        if (uri.scheme != "content") copies.add(uri)
                        else copyIn(context, uri)?.let { copies.add(it) }
                    }
                    if (copies.isEmpty()) return plainLaunch()
                    Intent(intent).apply {
                        putParcelableArrayListExtra(Intent.EXTRA_STREAM, copies)
                        clipData = null
                    }
                }
                else -> intent
            }
        } catch (_: Exception) {
            // Something unexpected: never pass the raw links on.
            plainLaunch()
        }
    }

    private fun plainLaunch() = Intent(Intent.ACTION_MAIN)

    /** Copies [uri] into a fresh folder of its own; null if it can't be read. */
    private fun copyIn(context: Context, uri: Uri): Uri? {
        val root = File(context.cacheDir, FOLDER)
        clearOld(root)
        val dir = File(root, System.nanoTime().toString())
        if (!dir.mkdirs()) return null
        var file = File(dir, cleanName(displayName(context, uri)))
        // Belt and braces: whatever the name, the copy stays in its folder.
        if (file.canonicalFile.parentFile != dir.canonicalFile) {
            file = File(dir, "shared")
        }
        val input = context.contentResolver.openInputStream(uri) ?: return null
        input.use { src -> file.outputStream().use { src.copyTo(it) } }
        return Uri.fromFile(file)
    }

    private fun displayName(context: Context, uri: Uri): String? = try {
        context.contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    } catch (_: Exception) {
        null
    }

    /** The last part of [raw] only, with no path, leading dots or odd marks. */
    private fun cleanName(raw: String?): String {
        val last = raw.orEmpty().substringAfterLast('/').substringAfterLast('\\')
        val clean = last.replace(Regex("[\\u0000-\\u001f:*?\"<>|]"), "_")
            .trim()
            .trimStart('.')
        return clean.take(120).ifEmpty { "shared" }
    }

    /** Removes copies from earlier shares, once the app has had a day to read them. */
    private fun clearOld(root: File) {
        val now = System.currentTimeMillis()
        root.listFiles()?.forEach { dir ->
            if (now - dir.lastModified() > KEEP_MS) dir.deleteRecursively()
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamsOf(intent: Intent): ArrayList<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
}
