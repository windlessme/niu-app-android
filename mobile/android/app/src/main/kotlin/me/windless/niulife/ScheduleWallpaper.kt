package me.windless.niulife

import android.app.Activity
import android.app.WallpaperManager
import android.content.ContentValues
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream

/** Only PNG bytes the app rendered cross this bridge; the photo library is never read. */
class ScheduleWallpaper(private val activity: Activity) {
    fun handle(method: String, bytes: ByteArray?, target: String?, result: MethodChannel.Result) {
        Thread {
            val outcome = runCatching {
                require(bytes != null && bytes.size in 8..(40 * 1024 * 1024) &&
                    bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)))
                when (method) {
                    "setWallpaper" -> {
                        val flags = when (target) {
                            "lock" -> WallpaperManager.FLAG_LOCK
                            "both" -> WallpaperManager.FLAG_LOCK or WallpaperManager.FLAG_SYSTEM
                            else -> throw IllegalArgumentException("target")
                        }
                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            ?: throw IllegalArgumentException("image")
                        WallpaperManager.getInstance(activity).setBitmap(bitmap, null, true, flags)
                        true
                    }
                    // Android 10+ adds to Pictures without any storage permission.
                    "saveImage" -> {
                        if (Build.VERSION.SDK_INT < 29) return@runCatching false
                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, "NIU-Life 課表桌布 ${System.currentTimeMillis()}.png")
                            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/NIU-Life")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                        val resolver = activity.contentResolver
                        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("insert")
                        try {
                            resolver.openOutputStream(uri)!!.use { ByteArrayInputStream(bytes).copyTo(it) }
                            values.clear()
                            values.put(MediaStore.Images.Media.IS_PENDING, 0)
                            resolver.update(uri, values, null, null)
                        } catch (e: Exception) {
                            resolver.delete(uri, null, null)
                            throw e
                        }
                        true
                    }
                    else -> null
                }
            }
            activity.runOnUiThread {
                outcome.fold(
                    { if (it == null) result.notImplemented() else result.success(it) },
                    { result.error("wallpaper_error", "無法設定或儲存桌布", null) },
                )
            }
        }.start()
    }
}
