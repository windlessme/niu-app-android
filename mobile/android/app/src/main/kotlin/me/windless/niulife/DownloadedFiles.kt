package me.windless.niulife

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

/** Opens a file Flutter downloaded into cache/attachments in another app. */
internal object DownloadedFiles {
    fun directory(activity: Activity) = activity.cacheDir.resolve("attachments")

    /** False when no installed app can open this type. */
    fun open(activity: Activity, path: String): Boolean {
        val file = File(path).canonicalFile
        val root = directory(activity).canonicalFile
        require(file.isFile && file.path.startsWith(root.path + File.separator))
        val type = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.calendar", file)
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newRawUri(file.name, uri)
        return try {
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
