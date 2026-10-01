package me.windless.niulife

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import java.time.Instant

internal object ScheduleReminders {
    private const val channel = "classes_v1"
    private const val requestCode = 100
    fun permitted(c: Context): Boolean = (Build.VERSION.SDK_INT < 33 ||
        c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        c.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    private fun pending(c: Context) = PendingIntent.getBroadcast(c, requestCode,
        Intent(c, ScheduleAlarmReceiver::class.java).setAction("me.windless.niulife.CLASS_REMINDER"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun cancel(c: Context) {
        c.getSystemService(AlarmManager::class.java).cancel(pending(c))
        c.getSystemService(NotificationManager::class.java).cancel(requestCode)
        ScheduleStore.prefs(c).edit().remove("nextAt").remove("nextTitle").remove("nextRoom").apply()
    }
    fun reschedule(c: Context) {
        cancel(c)
        val prefs = ScheduleStore.prefs(c)
        if (!prefs.getBoolean("reminders", false) || !permitted(c)) return
        val snapshot = ScheduleStore.load(c) ?: return
        val lead = prefs.getInt("lead", 10)
        val now = Instant.now()
        var date = now.atZone(scheduleZone).toLocalDate().coerceAtLeast(snapshot.start)
        var next: Instant? = null
        var selected: Block? = null
        while (date <= snapshot.end && next == null) {
            for (b in snapshot.on(date)) {
                val trigger = date.atStartOfDay(scheduleZone).plusMinutes((b.startMinute - lead).toLong()).toInstant()
                if (trigger > now && (next == null || trigger < next)) { next = trigger; selected = b }
            }
            date = date.plusDays(1)
        }
        if (next != null && selected != null) {
            prefs.edit().putLong("nextAt", next.toEpochMilli()).putString("nextTitle", selected.title)
                .putString("nextRoom", selected.room).apply()
            // Deliberately inexact: Doze and OEM battery policies can delay delivery.
            c.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, next.toEpochMilli(), pending(c))
        }
    }
    fun deliver(c: Context) {
        val prefs = ScheduleStore.prefs(c)
        val due = prefs.getLong("nextAt", 0)
        val now = System.currentTimeMillis()
        if (prefs.getBoolean("reminders", false) && ScheduleStore.load(c) != null &&
            permitted(c) && due > 0 && now >= due && now - due < 60 * 60 * 1000) {
            val manager = c.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(channel, "上課提醒", NotificationManager.IMPORTANCE_DEFAULT))
            val open = PendingIntent.getActivity(c, 11, Intent(c, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW).setData(Uri.parse("niulife://schedule")),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = Notification.Builder(c, channel).setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(prefs.getString("nextTitle", "上課提醒"))
                .setContentText(prefs.getString("nextRoom", ""))
                .setContentIntent(open).setAutoCancel(true).build()
            // reschedule cancels the prior notification before this new one is posted.
            reschedule(c)
            manager.notify(requestCode, notification)
        } else reschedule(c)
        ScheduleWidget.refresh(c)
    }
}

class ScheduleAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { ScheduleReminders.deliver(context) }
}

class ScheduleRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ScheduleReminders.reschedule(context)
        CampusNotifications.reschedule(context)
        ScheduleWidget.refresh(context)
    }
}
