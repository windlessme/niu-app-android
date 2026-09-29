package dev.niulife.prototype.niu_mobile

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Only validated PDF bytes cross this bridge; student URLs never enter intents. */
class RegistrationDocuments(private val activity: Activity) {
    private val directory get() = activity.cacheDir.resolve("registration_documents")
    private var pending: MethodChannel.Result? = null
    private var pendingFile: File? = null
    companion object { const val SAVE_REQUEST = 5031 }

    fun handle(method: String, bytes: ByteArray?, result: MethodChannel.Result) {
        try {
            if (method == "clear") {
                pending?.success(false)
                pending = null
                pendingFile = null
                directory.deleteRecursively()
                result.success(null)
                return
            }
            if (method != "viewPdf" && method != "savePdf") { result.notImplemented(); return }
            if (pending != null) { result.error("busy", "已有儲存作業進行中", null); return }
            require(bytes != null && bytes.size in 5..(20 * 1024 * 1024) &&
                bytes.copyOfRange(0, 5).contentEquals("%PDF-".toByteArray()))
            directory.mkdirs()
            directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000 }
                ?.forEach { it.delete() }
            val file = File.createTempFile("enrollment-", ".pdf", directory)
            file.writeBytes(bytes)
            if (method == "savePdf") {
                pending = result
                pendingFile = file
                activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE).setType("application/pdf")
                    .putExtra(Intent.EXTRA_TITLE, "在學證明.pdf"), SAVE_REQUEST)
            } else {
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.calendar", file)
                val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/pdf")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                intent.clipData = ClipData.newRawUri("在學證明", uri)
                activity.startActivity(intent)
                result.success(true)
            }
        } catch (_: Exception) {
            pending = null
            pendingFile?.delete()
            pendingFile = null
            result.error("document_error", "無法開啟或儲存 PDF", null)
        }
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SAVE_REQUEST) return
        val result = pending ?: return
        val file = pendingFile
        pending = null
        pendingFile = null
        try {
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null || file == null) result.success(false)
            else {
                activity.contentResolver.openOutputStream(uri, "wt")!!.use { output ->
                    file.inputStream().use { it.copyTo(output) }
                }
                result.success(true)
            }
        } catch (_: Exception) { result.error("save_error", "無法儲存 PDF", null) }
        finally { file?.delete() }
    }
}
