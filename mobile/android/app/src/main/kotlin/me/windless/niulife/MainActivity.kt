package me.windless.niulife

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Intent
import android.content.ClipData
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.content.FileProvider
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val registrationDocuments by lazy { RegistrationDocuments(this) }
    private val scheduleWallpaper by lazy { ScheduleWallpaper(this) }
    private var permissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "niulife/registration")
            .setMethodCallHandler { call, result ->
                registrationDocuments.handle(call.method, call.argument<ByteArray>("bytes"), result)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "niulife/wallpaper")
            .setMethodCallHandler { call, result ->
                scheduleWallpaper.handle(call.method, call.argument<ByteArray>("bytes"),
                    call.argument<String>("target"), result)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "niulife/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") return@setMethodCallHandler result.notImplemented()
                try {
                    result.success(DownloadedFiles.open(this, call.argument<String>("path")!!))
                } catch (_: Exception) { result.error("file_error", "無法開啟檔案", null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "niulife/app")
            .setMethodCallHandler { call, result ->
                if (call.method != "version") return@setMethodCallHandler result.notImplemented()
                try {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
                        else @Suppress("DEPRECATION") info.versionCode.toLong()
                    result.success(mapOf("name" to (info.versionName ?: ""), "build" to code.toString()))
                } catch (e: Exception) { result.error("version_error", e.message, null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "niulife/schedule")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "saveSnapshot" -> {
                            ScheduleStore.save(this, JSONObject(call.arguments as Map<*, *>))
                            result.success(null)
                        }
                        "clear" -> { ScheduleStore.clear(this); result.success(null) }
                        "setReminders" -> {
                            val lead = call.argument<Int>("minutesBefore") ?: 10
                            require(lead in 0..60)
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            ScheduleStore.prefs(this).edit().putBoolean("reminders", enabled)
                                .putInt("lead", lead).apply()
                            ScheduleReminders.reschedule(this)
                            result.success(!enabled || ScheduleReminders.permitted(this))
                        }
                        "setClassNow" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            ScheduleStore.prefs(this).edit().putBoolean(ClassInProgress.key, enabled).apply()
                            ClassInProgress.refresh(this)
                            result.success(!enabled || ScheduleReminders.permitted(this))
                        }
                        "reminderStatus" -> {
                            val snapshot = ScheduleStore.load(this)
                            result.success(mapOf(
                                "enabled" to ScheduleStore.prefs(this).getBoolean("reminders", false),
                                "classNow" to ScheduleStore.prefs(this).getBoolean(ClassInProgress.key, false),
                                "permitted" to ScheduleReminders.permitted(this),
                                "semesterStart" to snapshot?.start?.toString(),
                                "semesterEnd" to snapshot?.end?.toString(),
                            ))
                        }
                        "setNotifications" -> {
                            val kind = call.argument<String>("kind") ?: error("Missing kind")
                            val items = call.argument<List<Map<*, *>>>("items") ?: emptyList()
                            CampusNotifications.replace(this, kind, items)
                            result.success(null)
                        }
                        "requestNotificationPermission" -> {
                            if (Build.VERSION.SDK_INT >= 33 && !ScheduleReminders.permitted(this)) {
                                if (permissionResult != null) result.error("busy", "Permission request in progress", null)
                                else {
                                    permissionResult = result
                                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 200)
                                }
                            } else result.success(ScheduleReminders.permitted(this))
                        }
                        "shareCalendar" -> {
                            val ics = call.argument<String>("ics") ?: error("Missing calendar")
                            require(ics.startsWith("BEGIN:VCALENDAR\r\n") && ics.toByteArray().size <= 1024 * 1024)
                            val directory = cacheDir.resolve("calendar_exports").also { it.mkdirs() }
                            directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000 }
                                ?.forEach { it.delete() }
                            val file = java.io.File.createTempFile("niu-schedule-", ".ics", directory)
                            file.writeText(ics, Charsets.UTF_8)
                            val uri = FileProvider.getUriForFile(this, "$packageName.calendar", file)
                            val share = Intent(Intent.ACTION_SEND).setType("text/calendar")
                                .putExtra(Intent.EXTRA_STREAM, uri)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            share.clipData = ClipData.newRawUri("課表", uri)
                            startActivity(Intent.createChooser(share, "匯出課表"))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("schedule_error", e.message, null) }
            }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15+ draws edge to edge for apps targeting 35; older
        // versions get the same layout, which the Flutter UI already pads.
        WindowCompat.enableEdgeToEdge(window)
        super.onCreate(savedInstanceState)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        registrationDocuments.onResult(requestCode, resultCode, data)
    }
    override fun onResume() {
        super.onResume()
        ScheduleReminders.reschedule(this)
        ClassInProgress.refresh(this)
        CampusNotifications.reschedule(this)
        ScheduleWidget.refresh(this)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 200) {
            permissionResult?.success(ScheduleReminders.permitted(this))
            permissionResult = null
            ScheduleReminders.reschedule(this)
            ClassInProgress.refresh(this)
        }
    }
}
