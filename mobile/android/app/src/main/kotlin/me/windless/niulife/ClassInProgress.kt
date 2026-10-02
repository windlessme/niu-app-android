package me.windless.niulife

import android.app.*
import android.content.*
import android.net.Uri
import java.time.Instant
import java.time.LocalDate

/**
 * A quiet, ongoing notification while a class is under way: course, room,
 * a countdown to the end and the next class of the day, like the iOS Live
 * Activity. An inexact alarm wakes by the next change (this class's end or
 * the next one's start, see [wakeBy]); the countdown runs on the system
 * clock, and the notification removes itself at the end even if a wake is late.
 */
internal object ClassInProgress {
    const val key = "classNow"
    private const val channel = "class_now_v1"
    private const val notificationId = 102
    private const val requestCode = 102

    private fun pending(c: Context) = PendingIntent.getBroadcast(c, requestCode,
        Intent(c, ClassInProgressReceiver::class.java).setAction("me.windless.niulife.CLASS_NOW"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun cancel(c: Context) {
        c.getSystemService(AlarmManager::class.java).cancel(pending(c))
        c.getSystemService(NotificationManager::class.java).cancel(notificationId)
    }

    private fun at(date: LocalDate, minute: Int): Instant =
        date.atStartOfDay(scheduleZone).plusMinutes(minute.toLong()).toInstant()

    fun refresh(c: Context, now: Instant = Instant.now()) {
        val snapshot = ScheduleStore.load(c)
        if (!ScheduleStore.prefs(c).getBoolean(key, false) || snapshot == null ||
            !ScheduleReminders.permitted(c)) {
            cancel(c)
            return
        }
        val today = now.atZone(scheduleZone).toLocalDate()
        val blocks = snapshot.on(today)
        val current = blocks.firstOrNull { at(today, it.startMinute) <= now && now < at(today, it.endMinute) }
        val wake = if (current != null) {
            show(c, current, at(today, current.endMinute), blocks.firstOrNull { it.startMinute >= current.endMinute }, now)
            at(today, current.endMinute)
        } else {
            c.getSystemService(NotificationManager::class.java).cancel(notificationId)
            nextStart(snapshot, now)
        }
        val alarms = c.getSystemService(AlarmManager::class.java)
        // An early wake finds nothing changed and sets the next, closer one.
        if (wake == null) alarms.cancel(pending(c))
        else alarms.wakeBy(wake.toEpochMilli() + 1000, pending(c), now.toEpochMilli())
    }

    private fun nextStart(snapshot: Snapshot, now: Instant): Instant? {
        var date = now.atZone(scheduleZone).toLocalDate().coerceAtLeast(snapshot.start)
        while (date <= snapshot.end) {
            snapshot.on(date).map { at(date, it.startMinute) }.firstOrNull { it > now }?.let { return it }
            date = date.plusDays(1)
        }
        return null
    }

    private fun clock(minute: Int) = "%02d:%02d".format(minute / 60, minute % 60)

    private fun show(c: Context, block: Block, end: Instant, next: Block?, now: Instant) {
        val manager = c.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(channel, "上課中", NotificationManager.IMPORTANCE_LOW)
            .apply { description = "上課時顯示課名、教室與下課倒數" })
        val open = PendingIntent.getActivity(c, 12, Intent(c, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW).setData(Uri.parse("niulife://schedule")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val summary = listOf(block.room, "${clock(block.endMinute)} 下課").filter { it.isNotBlank() }
            .joinToString(" · ")
        val upcoming = next?.let {
            "下一堂 ${clock(it.startMinute)} ${it.title}" + if (it.room.isNotBlank()) " · ${it.room}" else ""
        }
        val notification = Notification.Builder(c, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(block.title)
            .setContentText(summary)
            .setSubText("上課中")
            .setStyle(Notification.BigTextStyle().bigText(listOfNotNull(summary, upcoming).joinToString("\n")))
            .setWhen(end.toEpochMilli())
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setTimeoutAfter(maxOf(1000L, end.toEpochMilli() - now.toEpochMilli()))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open)
            .build()
        manager.notify(notificationId, notification)
    }
}

class ClassInProgressReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { ClassInProgress.refresh(context) }
}
